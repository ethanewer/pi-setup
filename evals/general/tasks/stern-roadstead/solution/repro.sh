#!/bin/bash
# /app/repro.sh — canonical reproduction for the `.each` title-interpolation
# defect (oracle version).
#
# Drives the repository's own table machinery through the built jest-each
# package and a minimal global shim, then prints the generated test titles.
# Exits 0 only when the interpolation is correct; on the buggy tree the
# machinery records the unchanged title (the error is captured into the
# deferred test callback), the expected-output check fails, and the script
# exits non-zero.
set -u
node -e '
const each = require("/app/src/packages/jest-each").default;
const titles = [];
const mk = () => {
  const f = (...a) => { titles.push(a[0]); };
  f.skip = f; f.only = f; f.concurrent = f;
  f.concurrent.only = f; f.concurrent.skip = f;
  return f;
};
const g = {
  test: mk(), it: mk(), fit: mk(), xit: mk(), xtest: mk(),
  xdescribe: mk(), fdescribe: mk(), describe: mk(),
};
const t = each.withGlobal(g)([
  {"count(*)": 1, expected: "one"},
  {"count(*)": 2, expected: "two"},
]).test;
t("rows: $count(*) is $expected", () => {});
process.stdout.write(titles.join("\n") + "\n");
if (titles.join("|") !== "rows: 1 is one|rows: 2 is two") process.exit(1);
'