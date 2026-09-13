#!/bin/bash
# Oracle for capstan-fathom: applies the minimal upstream fix to the flake8
# checkout at /app/src (_extract_syntax_information must only treat the
# SyntaxError detail tuple as the pre-3.10 four-element layout when it really
# is one, and read the physical line from its stable absolute position), then
# proves the fix against the project's own regression test.
set -e

python3 /solution/fix_checker.py /app/src/src/flake8/checker.py

echo "== reproduction test (must now pass) =="
cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest \
  tests/integration/test_checker.py \
  -k test_handling_syntaxerrors_across_pythons \
  -q -W ignore::DeprecationWarning -p no:cacheprovider