#!/bin/bash
# Verifier for slate-anchor: enforces byte-integrity of the shipped legacy
# tree, checks the headless build contract (no X11 linkage, no X symbols),
# rebuilds with ./configure --without-x from a clean copy, and EXECUTES the
# deliverable binary on hidden job files against independently generated
# expected PBM images. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile

BINARY = "/app/plotsmith/plotsmith"
CONFIG = "/app/plotsmith/config.mk"
OUTMAP = "/app/out-map.pbm"
HIDDEN = "/tests/hidden"

failures = []

# --- byte-integrity of the shipped legacy tree ------------------------------
PRISTINE = {
    "/app/plotsmith/configure":
        "acc65acfa05cf5f81f91d1096babed00d2a76199781c49925cfc775b5c043605",
    "/app/plotsmith/Makefile":
        "42e2509cdd68a943724205f729f5261ac571191c901a3950bdd551cb8b86ce3a",
    "/app/plotsmith/core/canvas.c":
        "c9054e4ba1ba37eca9d1558e9c75d79ac57a3fbea4fbd09782fb73a64d7c66eb",
    "/app/plotsmith/core/canvas.h":
        "7bddf526a8cefd344037131cde9b5b2d7a27c9f394df43cb84588c9bd6556f8a",
    "/app/plotsmith/core/front.h":
        "f6090b6560b4674ff690770370eaf52ad8e1593640329f516c604ee809da8d63",
    "/app/plotsmith/core/front_null.c":
        "bc94c9476fa33b173d9bd44187fd15c2dea51cbd794fdde9b1c6707e29115435",
    "/app/plotsmith/core/job.c":
        "e51379fd0f1064f9f2adb73bfbba897f98788c3a4f16e22a528cc8940406fdef",
    "/app/plotsmith/core/job.h":
        "a7a0d8a5533e9b3f994acc2c4fedf6e96aa4303eac4c6d12407a7df983fa7056",
    "/app/plotsmith/core/main.c":
        "c420154531b5eba6b8c1d764c3b237216194d0eb147d85f3893accb6eb131a1e",
    "/app/plotsmith/core/pbm.c":
        "1de828c6ba108d65232981ccd8fc88ade9202712244581583481ce879d770cc8",
    "/app/plotsmith/core/pbm.h":
        "525cdf056464d5c3941e3597207e4f947ac76fcd3d6745c1111680983b73d89d",
    "/app/plotsmith/gui/xfront.c":
        "4d879da443cf6ef38216bca27aa12bd9d2acfb99156976c1e04d55396fa537d0",
    "/app/plotsmith/compat/xstub.c":
        "4751c2144ab9ce49c7c44036335ad5995df70000361c01206e44341b168436d5",
    "/app/plotsmith/compat/X11/Xlib.h":
        "b41155c11233495c213055b2b9e6a77baee0f5ba7dbbeecccab1e0629eea628d",
    "/app/jobs/visible-job.txt":
        "a2517c11ba972f726b38c6b40213adc1e4cf38c045a5a17b7087feab713d0ae0",
}
for path, want in PRISTINE.items():
    if not os.path.isfile(path):
        failures.append("shipped fixture missing: %s" % path)
        continue
    got = subprocess.run(["sha256sum", path], capture_output=True, text=True)
    if got.returncode != 0 or got.stdout.split()[0] != want:
        failures.append("shipped fixture modified: %s" % path)

# --- reference implementation of the documented engine contract -------------
W, H = 24, 16


def run_job(lines):
    pix = [0] * (W * H)

    def dot(x, y):
        if 0 <= x < W and 0 <= y < H:
            pix[y * W + x] = 1

    for raw in lines:
        t = raw.split()
        if not t or t[0].startswith('#'):
            continue
        verb, args = t[0], t[1:]
        try:
            vals = [int(v) for v in args]
        except ValueError:
            continue
        if verb == 'dot' and len(vals) == 2:
            dot(vals[0], vals[1])
        elif verb == 'hline' and len(vals) == 3:
            x1, x2, y = vals
            for x in range(min(x1, x2), max(x1, x2) + 1):
                dot(x, y)
        elif verb == 'vline' and len(vals) == 3:
            x, y1, y2 = vals
            for y in range(min(y1, y2), max(y1, y2) + 1):
                dot(x, y)
        elif verb in ('rect', 'fill') and len(vals) == 4:
            x, y, w, h = vals
            if w > 0 and h > 0:
                if verb == 'fill':
                    for yy in range(y, y + h):
                        for xx in range(x, x + w):
                            dot(xx, yy)
                else:
                    for xx in range(x, x + w):
                        dot(xx, y)
                        dot(xx, y + h - 1)
                    for yy in range(y, y + h):
                        dot(x, yy)
                        dot(x + w - 1, yy)
        elif verb == 'clear' and len(vals) == 0:
            pix[:] = [0] * (W * H)
    out = "P1\n%d %d\n" % (W, H)
    out += "\n".join(" ".join(str(pix[r * W + c]) for c in range(W))
                     for r in range(H))
    return out + "\n"


def check_x_free(exe, ctx):
    rd = subprocess.run(["readelf", "-d", exe], capture_output=True, text=True)
    dyn = rd.stdout + rd.stderr
    if re.search(r'(?i)x11', dyn):
        failures.append("%s: dynamic section references X11" % ctx)
    nm = subprocess.run(["nm", "-a", exe], capture_output=True, text=True)
    syms = nm.stdout + nm.stderr
    for bad in ("XOpenDisplay", "XCreateSimpleWindow", "XStoreName",
                "xfront"):
        if bad in syms:
            failures.append("%s: X-path symbol %s linked in" % (ctx, bad))


def run_case(exe, job, expected, ctx):
    if exe is None or not os.path.isfile(exe):
        failures.append("%s: cannot run (binary missing)" % ctx)
        return
    out = tempfile.mktemp(suffix=".pbm")
    r = subprocess.run([exe, job, out], capture_output=True, text=True,
                       timeout=60)
    if r.returncode != 0:
        failures.append("%s: exit %d" % (ctx, r.returncode))
        return
    try:
        got = open(out).read()
    except OSError:
        failures.append("%s: no output file" % ctx)
        return
    finally:
        if os.path.exists(out):
            os.remove(out)
    if got != expected:
        failures.append("%s: PBM output mismatch" % ctx)


# --- deliverable binary -----------------------------------------------------
rebuilt = None
if os.path.isfile(BINARY):
    check_x_free(BINARY, "deliverable")
else:
    failures.append("missing deliverable %s" % BINARY)

# --- config.mk must select the headless configuration -----------------------
if os.path.isfile(CONFIG):
    txt = open(CONFIG).read()
    if not re.search(r"HEADLESS\s*=\s*1\b", txt):
        failures.append("config.mk does not select the headless build")
else:
    failures.append("missing deliverable %s" % CONFIG)

# --- fresh rebuild with the X path excluded ---------------------------------
if os.path.isdir("/app/plotsmith"):
    tmp = tempfile.mkdtemp(prefix="slate-rebuild-")
    dst = os.path.join(tmp, "plotsmith")
    shutil.copytree("/app/plotsmith", dst,
                    ignore=shutil.ignore_patterns("*.o", "plotsmith",
                                                  "plotsmith-x", "config.mk",
                                                  "libX11*"))
    cfg = subprocess.run(["./configure", "--without-x"], cwd=dst,
                         capture_output=True, text=True, timeout=120)
    mk = subprocess.run(["make"], cwd=dst, capture_output=True, text=True,
                        timeout=180)
    cand = os.path.join(dst, "plotsmith")
    if cfg.returncode != 0 or mk.returncode != 0 or not os.path.isfile(cand):
        failures.append("clean './configure --without-x && make' failed")
    else:
        rebuilt = cand
        check_x_free(rebuilt, "rebuilt")

# --- hidden cases -----------------------------------------------------------
hidden = sorted(os.listdir(HIDDEN)) if os.path.isdir(HIDDEN) else []
if not hidden:
    failures.append("no hidden cases present")
for case in hidden:
    base = os.path.join(HIDDEN, case)
    job = os.path.join(base, "job.txt")
    exp = os.path.join(base, "expected.pbm")
    if not (os.path.isfile(job) and os.path.isfile(exp)):
        failures.append("hidden '%s' malformed" % case)
        continue
    expected = open(exp).read()
    if expected != run_job(open(job)):
        failures.append("hidden '%s': expected.pbm disagrees with reference "
                        "(fixture bug)" % case)
    run_case(BINARY, job, expected, "hidden '%s' (deliverable)" % case)
    run_case(rebuilt, job, expected, "hidden '%s' (rebuilt)" % case)

# --- visible-case deliverable ------------------------------------------------
run_case(BINARY, "/app/jobs/visible-job.txt",
         run_job(open("/app/jobs/visible-job.txt")),
         "visible re-run")
if os.path.isfile(OUTMAP):
    if open(OUTMAP).read() != run_job(open("/app/jobs/visible-job.txt")):
        failures.append("/app/out-map.pbm mismatch on visible job")
else:
    failures.append("missing deliverable %s" % OUTMAP)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
