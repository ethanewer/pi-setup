#!/bin/bash
set -euo pipefail
python3 - <<'EOF'
s = open('/app/legacy.c').read()
bug = 'printf("%c %s\\n", i, c);   /* format/argument mismatch (bug) */'
assert bug in s, "buggy line not found"
s = s.replace(bug, 'printf("c=%c i=%d\\n", c, i);')
open('/app/legacy.c','w').write(s)
EOF
gcc /app/legacy.c -o /app/legacy
/app/legacy > /app/run_output.txt
echo "wrote run_output.txt"