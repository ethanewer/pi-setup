#!/bin/bash
# Verifier for hazel-prism: enforces the source-size budget (raw + gzip caps),
# the no-embedded-pixels rule, the sizes report, and EXECUTES /app/frame.py on
# the default frames plus every hidden argument set, comparing byte-for-byte
# against an independent reference renderer. Writes REWARD to
# /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
trap '[ -f /logs/verifier/reward.txt ] || echo 0 > /logs/verifier/reward.txt' EXIT

python3 - <<'PY'
import gzip, json, os, subprocess, sys

SRC = "/app/frame.py"
REPORT = "/app/frame-sizes.json"
RAW_CAP = 900
GZIP_CAP = 480
RAMP = " .:-=+*#%@"

failures = []

# ---------------------------------------------------------------- budget ---
if not os.path.isfile(SRC):
    print("FAIL: missing", SRC)
    failures.append("missing frame.py")
    with open("/logs/verifier/reward.txt", "w") as fh:
        fh.write("0")
    sys.exit(0)

src_bytes = open(SRC, "rb").read()
gz = gzip.compress(src_bytes, 9)
print("measured source_bytes=%d gzip_bytes=%d" % (len(src_bytes), len(gz)))
if len(src_bytes) > RAW_CAP:
    failures.append("raw source %d > %d" % (len(src_bytes), RAW_CAP))
if len(gz) > GZIP_CAP:
    failures.append("gzip source %d > %d" % (len(gz), GZIP_CAP))

# ------------------------------------------------------- no embedded pixels ---
def ref_frame(mode, rows, cols):
    out = []
    for r in range(rows):
        line = []
        for c in range(cols):
            if mode == "mandel":
                cr = -2.1 + 3.0 * c / (cols - 1)
                ci = -1.2 + 2.4 * r / (rows - 1)
                z = 0j
                k = 0
                while k < 40 and abs(z) <= 2.0:
                    z = z * z + complex(cr, ci)
                    k += 1
            else:
                zr = -1.5 + 3.0 * c / (cols - 1)
                zi = -1.5 + 3.0 * r / (rows - 1)
                k = 0
                while k < 40 and zr * zr + zi * zi <= 4.0:
                    zr, zi = zr * zr - zi * zi - 0.7, 2.0 * zr * zi + 0.27015
                    k += 1
            line.append(RAMP[min(k * 9 // 40, 9)])
        out.append("".join(line))
    return "\n".join(out) + "\n"


def windows_of_interest(frame_text):
    """16-char windows with at least one non-space char, from every line."""
    wins = set()
    for line in frame_text.split("\n"):
        if len(line) < 16:
            continue
        for i in range(len(line) - 15):
            w = line[i:i + 16]
            if w.strip():
                wins.add(w)
    return wins


src_text = src_bytes.decode("utf-8", errors="replace")
for mode, rows, cols in (("mandel", 34, 92), ("julia", 36, 84)):
    art = ref_frame(mode, rows, cols)
    hits = [w for w in windows_of_interest(art) if w in src_text]
    if hits:
        failures.append("embedded pixel data detected (%d windows, e.g. %r)"
                        % (len(hits), hits[0]))

# ------------------------------------------------------------ sizes report ---
if not os.path.isfile(REPORT):
    failures.append("missing /app/frame-sizes.json")
else:
    try:
        rep = json.load(open(REPORT))
        assert isinstance(rep, dict)
        assert set(rep.keys()) == {"source_bytes", "gzip_bytes"}, rep.keys()
        assert all(isinstance(rep[k], int) for k in rep)
        if rep["source_bytes"] != len(src_bytes):
            failures.append("report source_bytes %s != %d" % (rep["source_bytes"], len(src_bytes)))
        if rep["gzip_bytes"] != len(gz):
            failures.append("report gzip_bytes %s != %d" % (rep["gzip_bytes"], len(gz)))
    except Exception as e:
        failures.append("frame-sizes.json unreadable/invalid: %s" % e)


def run_args(args, mode, rows, cols):
    out = subprocess.run([sys.executable, SRC] + [str(a) for a in args],
                         capture_output=True, text=True, timeout=120)
    if out.returncode != 0:
        return "exit %d: %s" % (out.returncode, out.stderr[:200])
    want = ref_frame(mode, rows, cols)
    if out.stdout != want:
        got_lines = out.stdout.split("\n")
        want_lines = want.split("\n")
        if len(got_lines) != len(want_lines):
            return "line count %d != %d" % (len(got_lines), len(want_lines))
        for i, (g, w) in enumerate(zip(got_lines, want_lines)):
            if g != w:
                return "row %d mismatch: got %r want %r" % (i, g[:40], w[:40])
        return "trailing bytes differ"
    return None


# ------------------------------------------------------ default frames ---
for mode, rows, cols in (("mandel", 34, 92), ("julia", 36, 84)):
    argv = [mode] if mode == "julia" else []
    err = run_args(argv, mode, rows, cols)
    if err:
        failures.append("default %s: %s" % (mode, err))

# ---------------------------------------------------------- hidden cases ---
hid = "/tests/hidden"
if os.path.isdir(hid):
    cases = sorted(d for d in os.listdir(hid) if os.path.isdir(os.path.join(hid, d)))
    if not cases:
        failures.append("no hidden cases present")
    for c in cases:
        argfile = os.path.join(hid, c, "args.txt")
        if not os.path.isfile(argfile):
            failures.append("hidden '%s': missing args.txt" % c)
            continue
        try:
            toks = open(argfile).read().split()
            assert toks, "empty args"
            mode = "mandel"
            nums = []
            for t in toks:
                if t in ("mandel", "julia"):
                    mode = t
                else:
                    nums.append(int(t))
            assert len(nums) == 2 and nums[0] >= 8 and nums[1] >= 8, toks
        except Exception as e:
            failures.append("hidden '%s': bad args (%s)" % (c, e))
            continue
        rows, cols = nums
        err = run_args(toks, mode, rows, cols)
        if err:
            failures.append("hidden '%s' (%s %dx%d): %s" % (c, mode, rows, cols, err))
else:
    failures.append("no /tests/hidden directory")

print("verify failures:", failures)
with open("/logs/verifier/reward.txt", "w") as fh:
    fh.write("1" if not failures else "0")
sys.exit(0)
PY
