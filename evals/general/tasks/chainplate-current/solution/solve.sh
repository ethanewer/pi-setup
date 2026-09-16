#!/bin/bash
# Oracle for chainplate-current: applies the minimal upstream fix to the mypy
# checkout at /app/src (in TypeChecker.visit_global_decl, only assign the
# global's type to the binder when get_declaration() returns a real type, so a
# still-unpinned partial type is never fed to binder.assign_type), then proves
# the CLI reproduction and the project's own golden regression case pass.
set -e

python3 /solution/fix_checker_global_partial.py /app/src/mypy/checker.py

cd /app/src

printf 'x = []\n\ndef f() -> None:\n    global x\n    x\n' > /tmp/repro.py
echo "== CLI reproduction =="
python3 -m mypy --no-incremental --allow-redefinition --cache-dir=/tmp/mycache /tmp/repro.py

echo "== golden regression test =="
python3 -m pytest mypy/test/testcheck.py \
    -k testLocalPartialTypesWithGlobalInitializedToEmptyListAndRedefine2 \
    -q -o addopts=""