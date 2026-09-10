#!/bin/bash
# Verifier for trunnel-reach.
# - requires the deliverable /app/solve.py
# - requires it to import angr and use angr.Project (symbolic execution, not an
#   enumeration or a hardcoded answer)
# - runs it against the visible binary and against every hidden case in
#   /tests/hidden, each hidden case compiled fresh with gcc from the authored
#   C source, and asserts the recovered 16 bytes make THAT binary print
#   ACCESS GRANTED and exit 0.
# Writes binary reward to /logs/verifier/reward.txt.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

fail() {
    echo "FAIL: $1" >&2
    echo 0 > /logs/verifier/reward.txt
    exit 0
}

[ -f /app/solve.py ] || fail "deliverable /app/solve.py is missing"
grep -q 'import angr' /app/solve.py || fail "deliverable does not import angr"
grep -q 'angr\.Project' /app/solve.py || fail "deliverable does not use angr.Project (must drive angr symbolic execution)"
python3 -c "import ast; ast.parse(open('/app/solve.py').read())" || fail "deliverable is not valid Python"

check_binary() {
    bin="$1"
    tag="$2"
    timeout 300 python3 /app/solve.py "$bin" > "/tmp/in_${tag}.bin" 2> "/tmp/solve_${tag}.err" || fail "solve.py failed or timed out on $tag"
    python3 "$BIN_CHECK" "$bin" "/tmp/in_${tag}.bin" "$tag" || fail "$tag: recovered input not accepted by the binary"
    echo "ok: $tag accepted the recovered input"
}

# helper script kept in the image-independent location: write it to /tmp
BIN_CHECK=/tmp/check_in.py
cat > /tmp/check_in.py <<'PYEOF'
import subprocess
import sys

binpath, inp_path, tag = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(inp_path, 'rb').read().rstrip(b'\n')
if len(data) != 16:
    print('FAIL %s: recovered %d bytes, expected 16' % (tag, len(data)))
    sys.exit(1)
if any(b < 0x20 or b > 0x7e for b in data):
    print('FAIL %s: recovered bytes are not printable ASCII' % tag)
    sys.exit(1)
p = subprocess.run([binpath], input=data, capture_output=True)
if p.returncode != 0:
    print('FAIL %s: binary exited %d' % (tag, p.returncode))
    sys.exit(1)
if b'ACCESS GRANTED' not in p.stdout:
    print('FAIL %s: no ACCESS GRANTED; stdout=%r' % (tag, p.stdout))
    sys.exit(1)
sys.exit(0)
PYEOF

# smoke: the visible binary
check_binary /app/challenge/crackme visible

# hidden generalization cases
i=0
for d in /tests/hidden/*/; do
    src="$d/crackme.c"
    [ -f "$src" ] || fail "hidden case $d has no crackme.c"
    i=$((i + 1))
    bin="/tmp/hidden_${i}"
    gcc -O1 -o "$bin" "$src" 2> "/tmp/gcc_${i}.err" || fail "could not compile hidden case $i"
    check_binary "$bin" "hidden_$i"
done

[ "$i" -ge 2 ] || fail "expected at least 2 hidden cases, found $i"

echo "ALL PASS"
echo 1 > /logs/verifier/reward.txt
exit 0