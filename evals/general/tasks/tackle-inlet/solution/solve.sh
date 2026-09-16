#!/bin/bash
# Oracle for tackle-inlet: applies the upstream-shaped fix to the real NLTK
# checkout at /app/src (the Hungarian Snowball stemmer must handle the empty
# string without crashing), installs the reproduction deliverable at
# /app/reproduce.py, and proves both: the project's own regression test
# (extracted from the fix release into /opt/golden) goes green, the
# reproduction passes against the repaired tree, and the neighbouring
# stemmer tests still pass.
set -euo pipefail

echo "== applying the fix to /app/src =="
python3 /solution/fix_snowball.py
git -C /app/src diff --stat
git -C /app/src diff | sed 's/^/    /' | head -30

echo "== writing the reproduction deliverable =="
cp /solution/reproduce.py /app/reproduce.py
chmod a+r /app/reproduce.py
python3 /app/reproduce.py

echo "== the project's own regression test (golden, from the fix release) =="
cd /tmp && python3 -m pytest -q -p no:cacheprovider /opt/golden/test_snowball.py

echo "== neighbouring stemmer tests from the project's own suite =="
cd /tmp && python3 -m pytest -q -p no:cacheprovider \
  /app/src/nltk/test/unit/test_stem.py::SnowballTest::test_russian \
  /app/src/nltk/test/unit/test_stem.py::SnowballTest::test_spanish \
  /app/src/nltk/test/unit/test_stem.py::SnowballTest::test_short_strings_bug \
  /app/src/nltk/test/unit/test_stem.py::PorterTest::test_lowercase_option \
  /app/src/nltk/test/unit/test_stem.py::PorterTest::test_oed_bug

echo "== oracle done =="