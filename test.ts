import { ChangeSetDescriptor, DB } from "./mod.ts";

const db = new DB("test.db");
db.exec("DROP TABLE IF EXISTS t");
db.exec("CREATE TABLE t(key TEXT PRIMARY KEY, value INT)");
const session = db.session().attach();
db.exec("INSERT INTO t VALUES(?, ?)", ["test", 2333]);
const stmt = db.prepare("SELECT * FROM t");
for (const item of stmt.query({})) {
  console.log(item);
}
const set = session.changeset();
console.log(...ChangeSetDescriptor.dump(set));
session.destroy();
db.exec("DELETE FROM t");
db.applyChangeSet(set);
for (const item of stmt.query({})) {
  console.log(item);
}
stmt.destroy();
