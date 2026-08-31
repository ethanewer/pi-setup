#!/bin/bash
# Verifier for cinder-keeper: enforces the no-modify rule on /app/keeper.c,
# compiles the visible gate, EXECUTES the deliverable crafter (/app/craft.py)
# on the visible source and on hidden gate sources in /tests/hidden, and
# feeds each crafted payload to the freshly compiled binaries. Writes REWARD
# (0/1) to /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_KEEPER_SHA="0066c5220a1be7b899b1d7ed4d794f44754ea3c4289d8e5928bad4452f306dcf"

no_modify_broken=0
if [ ! -f /app/keeper.c ]; then
    echo "no-modify: /app/keeper.c missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/keeper.c | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_KEEPER_SHA" ]; then
        echo "no-modify: /app/keeper.c was modified" >&2
        no_modify_broken=1
    fi
fi

export NO_MODIFY_BROKEN="$no_modify_broken"
python3 - <<'PY'
import json, os, re, shutil, subprocess, sys, tempfile

CRAFTER = "/app/craft.py"
failures = []

if os.environ.get("NO_MODIFY_BROKEN") == "1":
    failures.append("/app/keeper.c modified or missing (no-modify rule)")


def parse_src(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        src = fh.read()
    tl = re.search(r"#define\s+TAG_LEN\s+(\d+)\b", src)
    mg = re.search(r"#define\s+PERMIT_MAGIC\s+(0[xX][0-9a-fA-F]+|\d+)[uUlL]*", src)
    code = re.search(r'KEEPER_OPEN code=([A-Za-z0-9_\-]+)', src)
    if not (tl and mg and code):
        return None
    return int(tl.group(1)), int(mg.group(1), 0), code.group(1)


def run_case(src_path, workdir, tag, label):
    """Compile the gate, run the crafter, feed the payload. Returns bool."""
    info = parse_src(src_path)
    if info is None:
        return False
    tag_len, magic, code = info
    bin_path = os.path.join(workdir, "keeper_%s" % label)
    payload = os.path.join(workdir, "payload_%s.bin" % label)
    try:
        b = subprocess.run(["gcc", "-O0", "-o", bin_path, src_path],
                           capture_output=True, text=True, timeout=120)
        if b.returncode != 0:
            return False
        c = subprocess.run([sys.executable, CRAFTER, src_path, payload],
                           capture_output=True, text=True, timeout=60)
        if c.returncode != 0 or not os.path.isfile(payload):
            return False
        # length check: exactly TAG_LEN + 4 bytes, ending in LE magic
        with open(payload, "rb") as fh:
            blob = fh.read()
        if len(blob) != tag_len + 4:
            return False
        if blob[tag_len:] != magic.to_bytes(4, "little"):
            return False
        with open(payload, "rb") as fin:
            r = subprocess.run([bin_path], stdin=fin,
                               capture_output=True, text=True, timeout=60)
        return ("KEEPER_OPEN code=%s" % code) in r.stdout
    except Exception:
        return False


if not os.path.isfile(CRAFTER):
    failures.append("missing /app/craft.py")
else:
    work = tempfile.mkdtemp(prefix="cinder_vis_")
    try:
        # --- visible case: compile /app/keeper.c, craft, execute ---
        if not run_case("/app/keeper.c", work, "vis", "visible"):
            failures.append("visible case failed")
        # the shipped /app/exploit.bin must be the correct visible payload
        info = parse_src("/app/keeper.c")
        if info is None:
            failures.append("visible source unparseable")
        else:
            tag_len, magic, _ = info
            try:
                with open("/app/exploit.bin", "rb") as fh:
                    blob = fh.read()
                if len(blob) != tag_len + 4 or blob[tag_len:] != magic.to_bytes(4, "little"):
                    failures.append("exploit.bin is not the correct visible payload")
                # and it must actually open the freshly built gate
                bin_path = os.path.join(work, "keeper_shipped")
                b = subprocess.run(["gcc", "-O0", "-o", bin_path, "/app/keeper.c"],
                                   capture_output=True, text=True, timeout=120)
                if b.returncode == 0:
                    with open("/app/exploit.bin", "rb") as fin:
                        r = subprocess.run([bin_path], stdin=fin,
                                           capture_output=True, text=True, timeout=60)
                    if "KEEPER_OPEN" not in r.stdout:
                        failures.append("exploit.bin does not open the visible gate")
                else:
                    failures.append("visible gate failed to compile")
            except Exception:
                failures.append("exploit.bin unreadable")
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # --- hidden cases: fresh gate sources with different constants ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        work = tempfile.mkdtemp(prefix="cinder_hc_")
        try:
            for c in cases:
                src = os.path.join(hidden_dir, c, "keeper.c")
                if not os.path.isfile(src):
                    failures.append("hidden '%s' malformed" % c)
                    continue
                if not run_case(src, work, c, c):
                    failures.append("hidden case '%s' failed" % c)
        finally:
            shutil.rmtree(work, ignore_errors=True)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
