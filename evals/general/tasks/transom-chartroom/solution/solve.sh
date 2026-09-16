#!/bin/bash
# Oracle for transom-chartroom: applies the minimal upstream fix for the
# trailing-newline header-validity bug to the psf/requests checkout at
# /app/src (re-anchor the header name/value validity regexes from '$' to
# '\Z', so a name or value ending in a newline is rejected like any other
# return character), creates the reproduction deliverable, and proves the
# repaired tree passes the reproduction, the golden regression test and the
# project's unit-test slice.
set -e

# 1. fix the source (the real work; /solution/fix_header_validity.py holds the
#    exact upstream change applied to the pinned parent file).
python3 /solution/fix_header_validity.py /app/src

# 2. create the reproduction deliverable.
cp /solution/reproduce.py /app/reproduce_header_newline_bug.py
chmod 755 /app/reproduce_header_newline_bug.py

# 3. proof: the reproduction now passes on the repaired tree.
python3 /app/reproduce_header_newline_bug.py

# 4. proof: the project's own regression test (extracted at image build time
#    from the fix commit) passes 13/13 on the repaired tree.
cd /app/src
cp /opt/golden/test_requests.py tests/_golden_header_test.py
python3 -m pytest -q -p no:cacheprovider \
  tests/_golden_header_test.py -k header_no_return_chars
rm -f tests/_golden_header_test.py

# 5. proof: the project's unit-test slice stays green.
python3 -m pytest -q -p no:cacheprovider \
  tests/test_utils.py tests/test_hooks.py tests/test_structures.py

echo "ORACLE OK"