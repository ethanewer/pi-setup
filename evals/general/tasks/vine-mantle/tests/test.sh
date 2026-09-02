#!/bin/bash
# vine-mantle verifier. Checks only real /app artifacts; never reads /solution.
# Hidden inputs are mounted at /tests/hidden at verify time.
set -u

REWARD=1
fail() { echo "FAIL: $1" >&2; REWARD=0; }

# ----------------------------------------------------------- (1) solver + answer
[ -f /app/solve.py ] || fail "deliverable /app/solve.py missing"
[ -f /app/answer.json ] || fail "deliverable /app/answer.json missing"
if python3 - <<'EOF'
import json, sys
try:
    got = json.load(open("/app/answer.json"))
    exp = json.load(open("/tests/expected.json"))
    sys.exit(0 if got == exp else 1)
except Exception as e:
    print("answer.json parse/compare error:", e)
    sys.exit(1)
EOF
then :; else fail "answer.json does not match expected recovered credentials"; fi

# ------------------------------------------------------------ (1B) creds.txt
CCR=/app/result/creds.txt
[ -f "$CCR" ] || fail "creds result file missing"
grep -Eq '^(username|password):\s*.+' "$CCR" || fail "creds.txt has no username:/password: lines"

# ------------------------------------------------- (2) hidden generalization
EXP2=/tests/hidden/vault2_expected.json
BOX2=/tests/hidden/box2.7z
if [ -f "$BOX2" ] && [ -f "$EXP2" ] \
   && python3 /app/solve.py "$BOX2" /tmp/box2_out.json >/dev/null 2>&1 \
   && python3 - "$EXP2" /tmp/box2_out.json <<'EOF'
import json, sys
exp = json.load(open(sys.argv[1])); got = json.load(open(sys.argv[2]))
sys.exit(0 if got == exp else 1)
EOF
then :; else fail "solver did not generalize on the second encrypted archive"; fi

# ------------------------------------------------------------ (3) jar harness
if [ -f /app/dist/manta.jar ] \
   && java -cp /app/dist/manta.jar com.lattice.Probe /tests/hidden/jar_cases.txt > /tmp/jar.out 2>/dev/null \
   && diff -q /tmp/jar.out /tests/hidden/jar_expected.txt >/dev/null; then
    :
else
    fail "jar-upload resolver did not sanitize hidden filenames correctly"
fi

# --------------------------------------------------------------- (4) sanitize
REPO=/app/sanitize-repo
TOKEN='TKN-8v3K-99xq'
if [ ! -d "$REPO/.git" ]; then fail "sanitize repo has no git history"; else
    RESID=$(grep -ril "$TOKEN" --exclude-dir=.git "$REPO" 2>/dev/null)
    [ -z "${RESID:-}" ] || fail "daemon-token residue present: $RESID"
    [ -s "$REPO/config/app.env" ]   || fail "config/app.env missing/empty"
    [ -s "$REPO/docs/mapping.md" ]  || fail "docs/mapping.md missing/empty"
    CH=$( { git -C "$REPO" diff --name-only; git -C "$REPO" diff --cached --name-only; } | sort -u )
    EXPCH=$(printf 'config/app.env\ndocs/mapping.md\n')
    if [ "$CH" != "$EXPCH" ]; then fail "sanitize touched unexpected paths: $(echo "$CH" | tr '\n' ' ')"; fi
    if git -C "$REPO" status --porcelain | grep -Eq '^(\?\?|[MAUD]| RM)'; then
        fail "sanitize left untracked/added/deleted paths"
    fi
fi

# -------------------------------------------------------------------- (5) TLS
CRT=/app/tls/portico.test.crt
KEY=/app/tls/portico.test.key
if [ -f "$CRT" ] && [ -f "$KEY" ]; then
    SUBJ=$(openssl x509 -in "$CRT" -noout -subject -nameopt RFC2253 2>/dev/null)
    case "$SUBJ" in *CN=portico.test*) ;; *) fail "cert CN is not portico.test (got: $SUBJ)";; esac
    CM=$(openssl x509 -in "$CRT" -noout -modulus 2>/dev/null)
    KM=$(openssl rsa -in "$KEY" -noout -modulus 2>/dev/null)
    if [ "$CM" != "$KM" ]; then fail "tls certificate/private-key modulus mismatch"; fi
else
    fail "tls certificate/key deliverables missing"
fi

# -------------------------------------------------------------------- reward
mkdir -p /logs/verifier
echo "$REWARD" > /logs/verifier/reward.txt
echo "REWARD=$REWARD"