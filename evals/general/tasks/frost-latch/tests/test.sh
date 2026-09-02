#!/usr/bin/env bash
# frost-latch verifier (executes-deliverable).
# /app  = deliverables (bin/shelfscan, shelfscan.c, Makefile)
# /tests = read-only hidden cases mounted at verify time
# Writes 1/0 to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables exist ---------------------------------------------------- #
[ -x /app/bin/shelfscan ] || fail "missing/not executable /app/bin/shelfscan"
[ -f /app/shelfscan.c ]   || fail "missing /app/shelfscan.c"
[ -f /app/Makefile ]      || fail "missing /app/Makefile"
if [ "$reward" -eq 0 ]; then echo "0" > /logs/verifier/reward.txt; echo "final-reward=0"; exit 0; fi

# ---- 1. binary is a real ELF executable --------------------------------------- #
magic=$(head -c 4 /app/bin/shelfscan | od -An -tx1 | tr -d ' \n')
[ "$magic" = "7f454c46" ] || fail "/app/bin/shelfscan is not an ELF binary (magic=$magic)"

# ---- 2. Makefile + source genuinely rebuild the binary ------------------------ #
rm -rf /app/bin
if make -C /app >/tmp/fl_make.log 2>&1; then
  [ -x /app/bin/shelfscan ] || fail "make did not rebuild /app/bin/shelfscan"
else
  fail "make -C /app failed: $(tail -5 /tmp/fl_make.log)"
fi

# ---- 3-5. hidden functional cases, robustness, determinism -------------------- #
PY=$(cat <<'PY'
import glob, os, re, subprocess, sys

NUM = re.compile(r"[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?")

def load_weights(path):
    vals = []
    for line in open(path, encoding="utf-8"):
        line = line.split("#", 1)[0]
        for tok in line.split():
            if not NUM.fullmatch(tok):
                raise ValueError("bad token %r" % tok)
            vals.append(float(tok))
    return vals

def load_pgm(path):
    d = open(path, "rb").read()
    if d[:2] == b"P5":
        is5 = True
    elif d[:2] == b"P2":
        is5 = False
    else:
        raise ValueError("bad magic")
    pos = 2

    def nxt():
        nonlocal pos
        while pos < len(d):
            c = d[pos:pos+1]
            if c in b" \t\r\n\v\f":
                pos += 1
            elif c == b"#":
                while pos < len(d) and d[pos:pos+1] != b"\n":
                    pos += 1
            else:
                break
        start = pos
        while pos < len(d) and ord("0") <= d[pos] <= ord("9"):
            pos += 1
        if pos == start:
            raise ValueError("bad header")
        return int(d[start:pos])

    w, h, mv = nxt(), nxt(), nxt()
    if w < 1 or h < 1 or not (1 <= mv <= 65535):
        raise ValueError("bad dims")
    n = w * h
    if is5:
        bps = 1 if mv < 256 else 2
        pos += 1  # single whitespace after maxval
        if len(d) - pos < n * bps:
            raise ValueError("truncated")
        smp = [int.from_bytes(d[pos+i*bps:pos+(i+1)*bps], "big") for i in range(n)]
    else:
        smp = [nxt() for _ in range(n)]
    rows = [smp[r*w:(r+1)*w] for r in range(h)]
    return w, h, rows

def expected(wfn, ifn):
    wts = load_weights(wfn)
    width, height, rows = load_pgm(ifn)
    n = min(len(wts), width)
    resp = []
    for r in range(height):
        acc = 0.0
        for i in range(n):
            acc += wts[i] * float(rows[r][i])
        resp.append(acc)
    total = 0.0
    for v in resp:
        total += v
    best, worst = resp[0], resp[0]
    br = wr = 0
    for r in range(1, height):
        if resp[r] > best:
            best, br = resp[r], r
        if resp[r] < worst:
            worst, wr = resp[r], r
    mean = total / height
    return "max %d %.4f\nmin %d %.4f\nmean %.4f\n" % (br, best, wr, worst, mean)

fails = []
cases = sorted(glob.glob("/tests/hidden/*"))
if not cases:
    fails.append("no hidden cases present")
for d in cases:
    wfn, ifn = os.path.join(d, "weights.txt"), os.path.join(d, "image.pgm")
    if not (os.path.isfile(wfn) and os.path.isfile(ifn)):
        fails.append("%s: missing weights.txt/image.pgm" % d)
        continue
    try:
        exp = expected(wfn, ifn)
    except Exception as e:
        fails.append("%s: reference parse error %r" % (d, e))
        continue
    try:
        r = subprocess.run(["/app/bin/shelfscan", wfn, ifn],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0 or r.stdout != exp:
            fails.append("%s: rc=%d got %r want %r" % (d, r.returncode, r.stdout, exp))
    except Exception as e:
        fails.append("%s: %r" % (d, e))

# determinism: same input twice -> byte-identical stdout
try:
    d0 = cases[0]
    o1 = subprocess.run(["/app/bin/shelfscan", d0 + "/weights.txt", d0 + "/image.pgm"],
                        capture_output=True, timeout=30).stdout
    o2 = subprocess.run(["/app/bin/shelfscan", d0 + "/weights.txt", d0 + "/image.pgm"],
                        capture_output=True, timeout=30).stdout
    if o1 != o2:
        fails.append("nondeterministic stdout across identical runs")
except Exception as e:
    fails.append("determinism probe: %r" % e)

# robustness: wrong argument count -> nonzero, empty stdout
try:
    r = subprocess.run(["/app/bin/shelfscan", "only-one-arg"],
                       capture_output=True, text=True, timeout=30)
    if r.returncode == 0:
        fails.append("wrong-argcount: expected nonzero exit")
    if r.stdout != "":
        fails.append("wrong-argcount: expected empty stdout, got %r" % r.stdout)
except Exception as e:
    fails.append("wrong-argcount: %r" % e)

# robustness: missing weights file -> nonzero, empty stdout
try:
    d0 = cases[0]
    r = subprocess.run(["/app/bin/shelfscan", "/tmp/no_such_weights.txt", d0 + "/image.pgm"],
                       capture_output=True, text=True, timeout=30)
    if r.returncode == 0 or r.stdout != "":
        fails.append("missing-file: rc=%d stdout=%r" % (r.returncode, r.stdout))
except Exception as e:
    fails.append("missing-file: %r" % e)

if fails:
    print(" ; ".join(fails))
    sys.exit(1)
print("HIDDEN-CASES-PASS")
sys.exit(0)
PY
)
if python3 -c "$PY"; then :; else fail "hidden functional checks failed (see above)"; fi

# ---- finalize ------------------------------------------------------------------ #
echo "final-reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
