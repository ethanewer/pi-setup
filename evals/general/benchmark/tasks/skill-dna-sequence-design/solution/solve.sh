#!/bin/bash
set -euo pipefail
# A valid strand: A C G T A C G T A G
#   length 10, all four bases, no adjacent repeats, starts A, ends G, exactly two T's
python3 - <<'PY'
s = "ACGTACGTAG"
assert len(s) == 10
assert all(c in "ACGT" for c in s)
assert all(s.count(c) >= 1 for c in "ACGT")
assert all(s[i] != s[i+1] for i in range(len(s)-1))
assert s[0] == 'A' and s[-1] == 'G' and s.count('T') == 2
open('/app/designed.txt', 'w').write(s + '\n')
PY