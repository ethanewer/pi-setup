#!/bin/bash
# Convenience runner: the project's own multipart-adjacent tests, the way the
# verifier drives them. Must stay green on a correct fix.
set -e
cd /app/src
python3 -m pytest tests/sansio/test_multipart.py tests/test_formparser.py tests/test_wrappers.py -q -p no:cacheprovider "$@"