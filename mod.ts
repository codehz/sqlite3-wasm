import sqlite3, {
  dupe,
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

function bytesHelper<T>(bytes: Uint8Array, callback: (ptr: number) => T): T {
  const temp = dupe(bytes);
  try {
    return callback(temp);
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

export class DB {
  #handle: number;
  #cache = new Map<string, Statement>();
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

  destroy() {
    sqlite3.sqlite3_close(this.#handle);
  }
}

export type Value = number | string | Uint8Array | null;
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

  bind(
    idxOrName: number | string,
    value: Value,
  ): void {
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
        (ptr) => sqlite3.helper_bind_blob(this.#handle, idx, ptr, value.length),
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
    const datatype = sqlite3.sqlite3_column_type(this.#handle, idx);
    switch (datatype) {
      case 1:
      case 2:
        return sqlite3.sqlite3_column_double(this.#handle, idx);
      case 3: {
        const length = sqlite3.sqlite3_column_bytes(this.#handle, idx);
        return str(sqlite3.sqlite3_column_text(this.#handle, idx), length);
      }
      case 4: {
        const length = sqlite3.sqlite3_column_bytes(this.#handle, idx);
        return u8slice(sqlite3.sqlite3_column_text(this.#handle, idx), length);
      }
      case 5:
        return null;
      default:
        throw new TypeError(`invalid datetype: ${datatype}`);
    }
  }

  getObject(): Record<string | number, Value> {
    const ret: Record<string | number, Value> = [] as unknown as Record<
      string | number,
      Value
    >;
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
