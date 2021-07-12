import sqlite3, {
  dupe,
  sessionCallbacks,
  str,
  tocstr,
  tocstr2,
  u32slice,
  u8slice,
} from "./binding.ts";

sqlite3.sqlite3_initialize();

function stringHelper<T>(str: string, callback: (str: number) => T): T {
  const temp = tocstr(str);
  try {
    return callback(temp);
  } finally {
    sqlite3.free(temp);
  }
}
function stringHelper2<T>(
  str: string,
  callback: (addr: number, len: number) => T,
): T {
  const [addr, len] = tocstr2(str);
  try {
    return callback(addr, len);
  } finally {
    sqlite3.free(addr);
  }
}

function bytesHelper<T>(
  bytes: Uint8Array,
  callback: (ptr: number, len: number) => T,
): T {
  const temp = dupe(bytes);
  try {
    return callback(temp, bytes.length);
  } finally {
    sqlite3.free(temp);
  }
}

function errno() {
  return u32slice(sqlite3.helper_errno.value, 1)[0];
}
function resetErrno() {
  u32slice(sqlite3.helper_errno.value, 1)[0] = 0;
}

function swap() {
  return u32slice(sqlite3.helper_swap.value, 32);
}

export class SqliteError extends Error {
  constructor(code: number, message?: string) {
    const msg = message ?? str(sqlite3.sqlite3_errstr(code));
    super(`sqlite3 error: ${code}: ${msg}`);
  }
}

function throwIfError(code?: number) {
  const no = code ?? errno();
  if (no != 0) {
    resetErrno();
    throw new SqliteError(no);
  }
}

export type HandleConflict = "omit" | "abort";
export type HandleConflictReplace = HandleConflict | "replace";

export interface ChangeSetApplyHelper {
  filter?(name: string): boolean;
  onDataChanged?(desc: ConflictChangeSetDescriptor): HandleConflictReplace;
  onNotFound?(desc: ChangeSetDescriptor): HandleConflict;
  onDuplicate?(desc: ConflictChangeSetDescriptor): HandleConflictReplace;
  onForeignKey?(desc: ChangeSetDescriptor): HandleConflict;
  onConstraint?(desc: ChangeSetDescriptor): HandleConflict;
}

function mapConflict(res: string): number {
  switch (res) {
    case "omit":
      return 0;
    case "replace":
      return 1;
    case "abort":
      return 2;
    default:
      return 2;
  }
}

function setSessionCallback(helper: ChangeSetApplyHelper) {
  let key = 0;
  while (sessionCallbacks.has(key)) key++;
  sessionCallbacks.set(key, {
    filter(name: number): number {
      if (helper.filter) {
        return +helper.filter(str(name));
      } else {
        return 1;
      }
    },
    conflict(kind: number, iter: number) {
      const MAPS = [
        [helper.onDataChanged, ConflictChangeSetDescriptor],
        [helper.onNotFound, ChangeSetDescriptor],
        [helper.onDuplicate, ConflictChangeSetDescriptor],
        [helper.onForeignKey, ChangeSetDescriptor],
        [helper.onConstraint, ChangeSetDescriptor],
      ] as const;
      const [method, clazz] = MAPS[kind - 1];
      try {
        if (method) {
          return mapConflict(
            // deno-lint-ignore no-explicit-any
            method.call(helper, new clazz(iter) as any),
          );
        } else {
          return 2;
        }
      } catch (e) {
        console.error(e);
        return 2;
      }
    },
  });
  return key;
}

export class DB {
  #handle: number;
  constructor(filename: string) {
    this.#handle = stringHelper(filename, sqlite3.helper_open);
    throwIfError();
  }

  prepare(sql: string, persist = true) {
    const stmt = stringHelper(
      sql,
      (ptr) => sqlite3.helper_prepare(this.#handle, ptr, persist ? 1 : 0),
    );
    throwIfError();
    return new Statement(stmt);
  }

  exec(sql: string, param: Parameter = {}) {
    this.prepare(sql, false).excute(param).destroy();
  }

  session(name = "main") {
    const sess = stringHelper(
      name,
      (name) => sqlite3.helper_session_create(this.#handle, name),
    );
    throwIfError();
    return new Session(sess);
  }

  applyChangeSet(
    data: Uint8Array,
    helper: ChangeSetApplyHelper = {},
  ) {
    const id = setSessionCallback(helper);
    try {
      bytesHelper(
        data,
        (ptr, len) =>
          sqlite3.helper_changeset_apply(this.#handle, ptr, len, id),
      );
      throwIfError();
    } finally {
      sessionCallbacks.delete(id);
    }
  }

  destroy() {
    sqlite3.sqlite3_close(this.#handle);
  }
}

export type Value = number | string | Uint8Array | null;

function dumpValue(handle: number): Value {
  const type = sqlite3.sqlite3_value_type(handle);
  switch (type) {
    case 1:
    case 2:
      return sqlite3.sqlite3_value_double(handle);
    case 3: {
      const length = sqlite3.sqlite3_value_bytes(handle);
      return str(sqlite3.sqlite3_value_text(handle), length);
    }
    case 4: {
      const length = sqlite3.sqlite3_value_bytes(handle);
      return u8slice(sqlite3.sqlite3_value_blob(handle), length).slice(0);
    }
    case 5:
      return null;
    default:
      throw new TypeError(`invalid datetype: ${type}`);
  }
}

export class Session {
  #handle: number;
  constructor(handle: number) {
    this.#handle = handle;
  }

  attach(other?: string) {
    throwIfError(
      other
        ? stringHelper(
          other,
          (other) => sqlite3.sqlite3session_attach(this.#handle, other),
        )
        : sqlite3.sqlite3session_attach(this.#handle, 0),
    );
    return this;
  }

  changeset() {
    const addr = sqlite3.helper_session_changeset(this.#handle);
    throwIfError();
    try {
      const len = swap()[0];
      return u8slice(addr, len).slice(0);
    } finally {
      sqlite3.free(addr);
    }
  }

  patchset() {
    const addr = sqlite3.helper_session_patchset(this.#handle);
    throwIfError();
    try {
      const len = swap()[0];
      return u8slice(addr, len).slice(0);
    } finally {
      sqlite3.free(addr);
    }
  }

  destroy() {
    sqlite3.sqlite3session_delete(this.#handle);
  }
}

export type ChangeSetOperation = "unknown" | "insert" | "delete" | "update";

export class ChangeSetDescriptor {
  table: string;
  operation = "unknown";
  indirect: boolean;
  old?: Value[];
  new?: Value[];

  protected static capture(
    handle: number,
    count: number,
    method: (iterator: number, column: number) => number,
  ) {
    const ret: Value[] = [];
    for (let i = 0; i < count; i++) {
      const value = method(handle, i);
      throwIfError();
      ret.push(dumpValue(value));
    }
    return ret;
  }
  constructor(handle: number) {
    const nameref = sqlite3.helper_changeset_op(handle);
    throwIfError();
    this.table = str(nameref);
    const [column, operation, indirect] = swap();
    switch (operation) {
      case 18:
        this.operation = "insert";
        break;
      case 9:
        this.operation = "delete";
        break;
      case 23:
        this.operation = "update";
        break;
    }
    this.indirect = !!indirect;
    if (["delete", "update"].includes(this.operation)) {
      this.old = ChangeSetDescriptor.capture(
        handle,
        column,
        sqlite3.helper_changeset_old,
      );
    }
    if (["insert", "update"].includes(this.operation)) {
      this.new = ChangeSetDescriptor.capture(
        handle,
        column,
        sqlite3.helper_changeset_new,
      );
    }
  }

  static *dump(data: Uint8Array) {
    const handle = bytesHelper(
      data,
      sqlite3.helper_changeset_start,
    );
    throwIfError();
    try {
      while (true) {
        const op = sqlite3.sqlite3changeset_next(handle);
        if (op === 100) {
          yield new ChangeSetDescriptor(handle);
        } else if (op === 101) {
          return;
        } else {
          throw new SqliteError(op);
        }
      }
    } finally {
      sqlite3.sqlite3changeset_finalize(handle);
    }
  }
}

export class ConflictChangeSetDescriptor extends ChangeSetDescriptor {
  conflicts: Value[];
  constructor(handle: number) {
    super(handle);
    const [column] = swap();
    this.conflicts = ConflictChangeSetDescriptor.capture(
      handle,
      column,
      sqlite3.helper_changeset_conflict,
    );
  }
}

export type Parameter = Record<string, Value> | Value[];

export class Statement {
  #handle: number;
  #params: Record<string, number> = {};
  #results: string[] = [];
  constructor(handle: number) {
    this.#handle = handle;
    const paramCount = sqlite3.sqlite3_bind_parameter_count(this.#handle);
    for (let i = 1; i <= paramCount; i++) {
      const nameaddr = sqlite3.sqlite3_bind_parameter_name(this.#handle, i);
      if (nameaddr != 0) {
        this.#params[str(nameaddr)] = i;
      }
    }
    const columnCount = sqlite3.sqlite3_column_count(this.#handle);
    for (let i = 0; i < columnCount; i++) {
      this.#results.push(str(sqlite3.sqlite3_column_name(this.#handle, i)));
    }
  }

  step(): number {
    return sqlite3.sqlite3_step(this.#handle);
  }

  bind(idxOrName: number | string, value: Value): void {
    const idx = typeof idxOrName == "number"
      ? idxOrName
      : this.#params[idxOrName];
    if (idx == null) {
      throw new ReferenceError(`No param for ${idxOrName}`);
    }
    if (value == null) {
      throwIfError(sqlite3.sqlite3_bind_null(this.#handle, idx));
    } else if (value instanceof Uint8Array) {
      bytesHelper(
        value,
        (ptr, len) => sqlite3.helper_bind_blob(this.#handle, idx, ptr, len),
      );
      throwIfError();
    } else if (typeof value === "string") {
      stringHelper2(
        value,
        (addr, len) => sqlite3.helper_bind_text(this.#handle, idx, addr, len),
      );
      throwIfError();
    } else if (typeof value === "number") {
      throwIfError(sqlite3.sqlite3_bind_double(this.#handle, idx, value));
    }
  }

  get(idx: number): Value {
    if (idx < 0 && idx >= this.#results.length) {
      throw new RangeError("column out of range");
    }
    return dumpValue(sqlite3.sqlite3_column_value(this.#handle, idx));
  }

  getObject(): Record<string | number, Value> {
    const ret = [] as unknown as Record<string | number, Value>;
    for (let i = 0; i < this.#results.length; i++) {
      const value = this.get(i);
      ret[i] = value;
      ret[this.#results[i]] = value;
    }
    return ret;
  }

  bindAll(obj: Parameter) {
    if (Array.isArray(obj)) {
      for (let i = 0; i < obj.length; i++) {
        this.bind(i + 1, obj[i]);
      }
    } else {
      for (const key in obj) {
        this.bind(key, obj[key]);
      }
    }
  }

  *query(obj: Parameter = {}): Iterable<Record<string | number, Value>> {
    try {
      this.bindAll(obj);
      while (true) {
        const ret = this.step();
        if (ret == 100) {
          yield this.getObject();
        } else if (ret == 101) {
          return;
        } else {
          throwIfError(ret);
        }
      }
    } finally {
      throwIfError(sqlite3.sqlite3_reset(this.#handle));
      throwIfError(sqlite3.sqlite3_clear_bindings(this.#handle));
    }
  }

  excute(obj: Parameter = {}): Statement {
    try {
      this.bindAll(obj);
      const ret = this.step();
      if (ret == 100) {
        throw new TypeError("got row data");
      } else if (ret == 101) {
        return this;
      } else {
        throw new SqliteError(ret);
      }
    } finally {
      throwIfError(sqlite3.sqlite3_reset(this.#handle));
      throwIfError(sqlite3.sqlite3_clear_bindings(this.#handle));
    }
  }

  destroy() {
    throwIfError(sqlite3.sqlite3_finalize(this.#handle));
  }
}
