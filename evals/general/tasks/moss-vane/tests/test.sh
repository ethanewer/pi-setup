#!/usr/bin/env bash
# moss-vane verifier (executes-deliverable).
# Executes /app/bin/infer (and a clean recompile of /app/src/infer.c) on the
# visible fixture and hidden cases; writes 0/1 to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables exist and /app/bin/infer is a native ELF ------------- #
[ -x /app/bin/infer ]   || fail "missing/not executable /app/bin/infer"
[ -f /app/src/infer.c ] || fail "missing /app/src/infer.c"
if [ -f /app/bin/infer ]; then
  head -c 4 /app/bin/infer | grep -q $'\x7fELF' || fail "/app/bin/infer is not an ELF binary"
fi

# ---- 1. no-modify rule on the visible fixtures ---------------------------- #
FIX_W_SHA="9834aea4b94c8a350981a47928e8c6ab44e4793e522e35f5a1281542b73410f4"
FIX_I_SHA="a070755740756865b426014250347c5c991e4f8d55eb74a62aaba101f2bb3228"
if [ -f /app/fixtures/weights.txt ]; then
  [ "$(sha256sum /app/fixtures/weights.txt | awk '{print $1}')" = "$FIX_W_SHA" ] \
    || fail "/app/fixtures/weights.txt was modified"
else
  fail "/app/fixtures/weights.txt missing"
fi
if [ -f /app/fixtures/image.pgm ]; then
  [ "$(sha256sum /app/fixtures/image.pgm | awk '{print $1}')" = "$FIX_I_SHA" ] \
    || fail "/app/fixtures/image.pgm was modified"
else
  fail "/app/fixtures/image.pgm missing"
fi

# ---- 2. recompile the source; rebuilt binary must behave identically ------ #
rm -f /tmp/infer_rebuild
if ! gcc -O2 -o /tmp/infer_rebuild /app/src/infer.c 2>/tmp/rebuild.log; then
  fail "recompile of /app/src/infer.c failed: $(tail -3 /tmp/rebuild.log)"
fi

# ---- 3. hidden functional checks against an independent reference --------- #
PY=$(cat <<'PY'
import glob, os, re, subprocess, sys

BIN = "/app/bin/infer"
REB = "/tmp/infer_rebuild"
FIX_W, FIX_I = "/app/fixtures/weights.txt", "/app/fixtures/image.pgm"

def strip_comments(text):
    out = []
    for line in text.split("\n"):
        i = line.find("#")
        if i >= 0:
            line = line[:i]
        out.append(line)
    return out

def tokens(text):
    t = []
    for line in strip_comments(text):
        t += line.split()
    return t

INT_RE = re.compile(r"[+-]?[0-9]+")

def expected(weights_path, image_path):
    """Independent reference; raises on malformed inputs."""
    wt = tokens(open(weights_path).read())
    for tok in wt:
        if not INT_RE.fullmatch(tok):
            raise ValueError("bad weights token %r" % tok)
    w = [int(x) for x in wt] + [0] * 16
    pt = tokens(open(image_path).read())
    if not pt or pt[0] != "P2":
        raise ValueError("bad image magic")
    if len(pt) < 4:
        raise ValueError("short header")
    W, H, M = int(pt[1]), int(pt[2]), int(pt[3])
    if W < 1 or H < 1 or not (1 <= M <= 65535):
        raise ValueError("bad header values")
    pix_tokens = pt[4:4 + W * H]
    if len(pix_tokens) != W * H or pt[4 + W * H:]:
        raise ValueError("pixel count / trailing data")
    pix = [int(x) for x in pix_tokens]
    if any(v < 0 or v > M for v in pix):
        raise ValueError("pixel out of range")
    score = 0
    for br in range(4):
        for bc in range(4):
            r0, r1 = (br * H) // 4, ((br + 1) * H) // 4
            c0, c1 = (bc * W) // 4, ((bc + 1) * W) // 4
            s = sum(pix[r * W + c] for r in range(r0, r1) for c in range(c0, c1))
            score += w[4 * br + bc] * s
    cls = "POS" if score > 0 else ("NEG" if score < 0 else "ZERO")
    return "score=%d\nclass=%s\n" % (score, cls)

def run(prog, args):
    try:
        r = subprocess.run([prog] + args, capture_output=True, text=True, timeout=60)
        return r.returncode, r.stdout
    except Exception as e:
        return -99, "EXC:%r" % (e,)

fails = []
if not os.path.isfile(BIN):
    print("missing deliverable binary"); sys.exit(1)

progs = [("bin", BIN)]
if os.path.isfile(REB):
    progs.append(("rebuild", REB))
else:
    fails.append("rebuild binary missing")

# visible fixture (ok case)
try:
    want = expected(FIX_W, FIX_I)
    for label, p in progs:
        rc, out = run(p, [FIX_W, FIX_I])
        if rc != 0 or out != want:
            fails.append("fixture %s: rc=%d out=%r want=%r" % (label, rc, out, want))
except Exception as e:
    fails.append("fixture reference failed: %r" % (e,))

# hidden cases
cases = sorted(glob.glob("/tests/hidden/*"))
if not cases:
    print("NO HIDDEN CASES"); sys.exit(1)
for d in cases:
    wp, ip = os.path.join(d, "weights.txt"), os.path.join(d, "image.pgm")
    ef = os.path.join(d, "expect.txt")
    if not (os.path.isfile(wp) and os.path.isfile(ip) and os.path.isfile(ef)):
        fails.append("%s: malformed hidden case dir" % d)
        continue
    mode = open(ef).read().strip()
    if mode == "ok":
        try:
            want = expected(wp, ip)
        except Exception as e:
            fails.append("%s: reference failed on ok case: %r" % (d, e))
            continue
        for label, p in progs:
            rc, out = run(p, [wp, ip])
            if rc != 0 or out != want:
                fails.append("%s %s: rc=%d out=%r want=%r" % (label, d, rc, out, want))
    elif mode == "error":
        for label, p in progs:
            rc, out = run(p, [wp, ip])
            if rc == 0 or out != "":
                fails.append("%s %s: expected failure, got rc=%d out=%r" % (label, d, rc, out))
    else:
        fails.append("%s: bad expect.txt" % d)

# argument-order is literal: swapping must not yield the correct-order result
try:
    want = expected(FIX_W, FIX_I)
    rc, out = run(BIN, [FIX_I, FIX_W])
    if rc == 0 and out == want:
        fails.append("swapped args produced the weights-then-image result")
except Exception:
    pass

# bad argument count -> nonzero exit
rc, out = run(BIN, ["/app/fixtures/weights.txt"])
if rc == 0:
    fails.append("one-arg invocation exited 0")

# missing weights file -> nonzero exit, empty stdout
rc, out = run(BIN, ["/tmp/definitely_missing_weights.dat", FIX_I])
if rc == 0 or out != "":
    fails.append("missing-weights invocation: rc=%d out=%r" % (rc, out))

if fails:
    print(" ; ".join(fails)); sys.exit(1)
print("HIDDEN-CASES-PASS"); sys.exit(0)
PY
)
if python3 -c "$PY"; then :; else fail "hidden functional checks failed (see above)"; fi

# ---- finalize -------------------------------------------------------------- #
echo "final-reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
