// deno-lint-ignore-file
import * as vfs from "./vfs.ts";

const file = await Deno.readFile("./zig-out/lib/sqlite3.wasm");
const encoder = new TextEncoder();
const decoder = new TextDecoder();
function exports() {
  return mod.instance.exports as unknown as SQLite3Library;
}
export function mem() {
  return exports().memory;
}
export function u32slice(ptr: number, len: number): Uint32Array {
  return new Uint32Array(mem().buffer, ptr, len);
}
export function u8slice(ptr: number, len: number): Uint8Array {
  return new Uint8Array(mem().buffer, ptr, len);
}
export function str(ptr: number, len?: number): string {
  return decoder.decode(u8slice(ptr, len ?? exports().strlen(ptr)));
}
export function dupe(arr: Uint8Array): number {
  const addr = exports().malloc(arr.length);
  u8slice(addr, arr.length).set(arr);
  return addr;
}
export function tocstr(text: string): number {
  const buf = encoder.encode(text);
  const addr = exports().malloc(buf.length + 1);
  u8slice(addr, buf.length).set(buf);
  u8slice(addr + buf.length, 1).set([0]);
  return addr;
}
export function tocstr2(text: string): [number, number] {
  const buf = encoder.encode(text);
  const addr = exports().malloc(buf.length);
  u8slice(addr, buf.length).set(buf);
  return [addr, buf.length];
}
const mod = await WebAssembly.instantiate(file, {
  host: {
    console_log(buffer: number, length: number) {
      const content = str(buffer, length);
      console.log(content);
    },
    console_error(buffer: number, length: number) {
      const content = str(buffer, length);
      console.error(content);
    },
    get_time(): number {
      return +new Date();
    },
    fill_random(buffer: number, size: number) {
      crypto.getRandomValues(u8slice(buffer, size));
    },
    fs_access(filename: number, length: number, flags: number): number {
      const path = str(filename, length);
      return vfs.access(path, flags);
    },
    fs_open(filename: number, length: number, flags: number): number {
      console.log("open");
      const path = str(filename, length);
      return vfs.open(path, flags);
    },
    fs_close: vfs.close,
    fs_delete(filename: number) {
      vfs.deleteFile(str(filename));
    },
    fs_read(
      fd: number,
      buffer: number,
      length: number,
      offset: number,
    ): number {
      return vfs.read(fd, u8slice(buffer, length), offset);
    },
    fs_write(
      fd: number,
      buffer: number,
      length: number,
      offset: number,
    ): number {
      return vfs.write(fd, u8slice(buffer, length), offset);
    },
    fs_truncate: vfs.truncate,
    fs_filesize: vfs.filesize,
  },
});

interface SQLite3Library {
  memory: WebAssembly.Memory;
  helper_errno: WebAssembly.Global;
  malloc(size: number): number;
  free(ptr: number): void;
  realloc(ptr: number, size: number): number;
  strlen(ptr: number): number;
  sqlite3_errstr(code: number): number;
  sqlite3_errmsg(db: number): number;
  sqlite3_initialize(): void;
  helper_open(filename: number): number;
  sqlite3_close(db: number): void;
  helper_prepare(
    db: number,
    sql: number,
    flags: number,
  ): number;
  sqlite3_finalize(stmt: number): number;
  sqlite3_step(stmt: number): number;
  sqlite3_reset(stmt: number): number;
  sqlite3_bind_parameter_count(stmt: number): number;
  sqlite3_bind_parameter_index(stmt: number, name: number): number;
  sqlite3_bind_parameter_name(stmt: number, idx: number): number;
  helper_bind_blob(stmt: number, idx: number, data: number, len: number): void;
  helper_bind_text(stmt: number, idx: number, data: number, len: number): void;
  sqlite3_bind_double(stmt: number, idx: number, value: number): number;
  sqlite3_bind_null(stmt: number, idx: number): number;
  sqlite3_column_type(stmt: number, idx: number): number;
  sqlite3_column_count(stmt: number): number;
  sqlite3_column_name(stmt: number, idx: number): number;
  sqlite3_column_double(stmt: number, idx: number): number;
  sqlite3_column_bytes(stmt: number, idx: number): number;
  sqlite3_column_text(stmt: number, idx: number): number;
  sqlite3_column_blob(stmt: number, idx: number): number;
  sqlite3_reset(stmt: number): number;
  sqlite3_clear_bindings(stmt: number): number;
}

export default exports();
