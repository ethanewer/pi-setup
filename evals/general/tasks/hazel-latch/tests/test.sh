#!/usr/bin/env bash
# hazel-latch verifier (executes-deliverable).
# Boots /app/bin/latch-engine (and a clean recompile of /app/src/latch_engine.c)
# through the external launcher and against an independent framed-protocol
# reference on hidden sessions; writes 0/1 to /logs/verifier/reward.txt.
set -uo pipefail
mkdir -p /logs/verifier
reward=1
fail(){ echo "FAIL: $*" >&2; reward=0; }

# ---- 0. deliverables exist and /app/bin/latch-engine is a native ELF ------- #
[ -x /app/bin/latch-engine ]   || fail "missing/not executable /app/bin/latch-engine"
[ -f /app/src/latch_engine.c ] || fail "missing /app/src/latch_engine.c"
if [ -f /app/bin/latch-engine ]; then
  head -c 4 /app/bin/latch-engine | grep -q $'\x7fELF' || fail "/app/bin/latch-engine is not an ELF binary"
fi

# ---- 1. no-modify rule on the immutable lab inputs -------------------------- #
L_SHA="bb5b6539ec7d34b03b37a16ef7c227a318dbd406eaf01f8d911050ee1c3994b4"
S_SHA="680b9414911016ac1e00c66ee0764140388b9c8b14f51d1d93f0f485ab9c1c1e"
if [ -f /app/launcher.mjs ]; then
  [ "$(sha256sum /app/launcher.mjs | awk '{print $1}')" = "$L_SHA" ] \
    || fail "/app/launcher.mjs was modified"
else
  fail "/app/launcher.mjs missing"
fi
if [ -f /app/samples/session.txt ]; then
  [ "$(sha256sum /app/samples/session.txt | awk '{print $1}')" = "$S_SHA" ] \
    || fail "/app/samples/session.txt was modified"
else
  fail "/app/samples/session.txt missing"
fi

# ---- 2. recompile the source ------------------------------------------------ #
rm -f /tmp/latch_rebuild
if ! gcc -O2 -o /tmp/latch_rebuild /app/src/latch_engine.c 2>/tmp/latch_rebuild.log; then
  fail "recompile of /app/src/latch_engine.c failed: $(tail -3 /tmp/latch_rebuild.log)"
fi

# ---- 3. hidden functional checks -------------------------------------------- #
PY=$(cat <<'PY'
import glob, os, re, subprocess, sys, zlib

BIN = "/app/bin/latch-engine"
REB = "/tmp/latch_rebuild"

def parse_session(path):
    seed = None
    reqs = []
    for raw in open(path).read().splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if seed is None:
            if not line.startswith("seed="):
                raise ValueError("first line must be seed=")
            seed = int(line[5:])
            if not (0 <= seed <= 4294967295):
                raise ValueError("seed out of range")
            continue
        if not re.fullmatch(r"[0-9]+", line):
            raise ValueError("bad request line")
        n = int(line)
        if n > 1000000:
            raise ValueError("request too large")
        reqs.append(n)
    if seed is None:
        raise ValueError("no seed line")
    return seed, reqs

def expected_frames(seed, reqs):
    s = seed & 0xFFFFFFFF
    out = []
    for n in reqs:
        letters = []
        for _ in range(n):
            s = (s * 1664525 + 1013904223) & 0xFFFFFFFF
            letters.append(chr(97 + ((s >> 7) % 26)))
        payload = "".join(letters)
        crc = zlib.crc32(payload.encode("latin-1")) & 0xFFFFFFFF
        out.append("BEGIN %d\n%s\nEND %08x\n" % (n, payload, crc))
    return "".join(out)

def run(prog, args, inp=None):
    try:
        r = subprocess.run([prog] + args, input=inp, capture_output=True,
                           text=True, timeout=60)
        return r.returncode, r.stdout, r.stderr
    except Exception as e:
        return -99, "EXC:%r" % (e,), ""

fails = []
if not os.path.isfile(BIN):
    print("missing deliverable binary"); sys.exit(1)

progs = [("bin", BIN)]
if os.path.isfile(REB):
    progs.append(("rebuild", REB))
else:
    fails.append("rebuild binary missing")

# probe banner: exact, exit 0, nothing else
for label, p in progs:
    rc, out, err = run(p, ["--probe"])
    if rc != 0 or out != "LATCH/1 READY\n":
        fails.append("probe %s: rc=%d out=%r" % (label, rc, out))

cases = sorted(glob.glob("/tests/hidden/case*.txt"))
if not cases:
    print("NO HIDDEN CASES"); sys.exit(1)
for path in cases:
    try:
        seed, reqs = parse_session(path)
        want = expected_frames(seed, reqs)
    except Exception as e:
        fails.append("%s: reference failed: %r" % (path, e))
        continue
    inp = "".join(str(n) + "\n" for n in reqs)
    for label, p in progs:
        rc, out, err = run(p, ["--serve", str(seed)], inp)
        if rc != 0 or out != want:
            fails.append("serve %s %s: rc=%d first-diff=%s" % (
                label, path, rc,
                next((i for i, (a, b) in enumerate(zip(out, want)) if a != b),
                     min(len(out), len(want)))))
    # external launcher must boot and fully verify the session
    try:
        r = subprocess.run(["node", "/app/launcher.mjs", path],
                           capture_output=True, text=True, timeout=90)
        if r.returncode != 0 or "SESSION_OK %d" % len(reqs) not in r.stdout \
                or "BOOT_FAIL" in r.stdout + r.stderr \
                or "FRAME_FAIL" in r.stdout + r.stderr:
            fails.append("launcher %s: rc=%d out=%r err=%r" % (
                path, r.returncode, r.stdout[-200:], r.stderr[-200:]))
    except Exception as e:
        fails.append("launcher %s: %r" % (path, e))

# visible sample session through the launcher as well
try:
    r = subprocess.run(["node", "/app/launcher.mjs", "/app/samples/session.txt"],
                       capture_output=True, text=True, timeout=90)
    if r.returncode != 0 or "SESSION_OK 3" not in r.stdout:
        fails.append("launcher sample: rc=%d out=%r" % (r.returncode, r.stdout[-200:]))
except Exception as e:
    fails.append("launcher sample: %r" % (e,))

# bad usage -> nonzero exit, no stdout
rc, out, _ = run(BIN, [])
if rc == 0 or out != "":
    fails.append("no-arg invocation: rc=%d out=%r" % (rc, out))
rc, out, _ = run(BIN, ["--serve", "notanumber"], "")
if rc == 0 or out != "":
    fails.append("bad-seed invocation: rc=%d out=%r" % (rc, out))

if fails:
    print(" ; ".join(fails)); sys.exit(1)
print("HIDDEN-CASES-PASS"); sys.exit(0)
PY
)
if python3 -c "$PY"; then :; else fail "hidden functional checks failed (see above)"; fi

# ---- finalize ---------------------------------------------------------------- #
echo "final-reward=$reward"
echo "$reward" > /logs/verifier/reward.txt
exit 0
