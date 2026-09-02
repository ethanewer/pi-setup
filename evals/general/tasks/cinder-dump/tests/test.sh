#!/bin/bash
# Verifier for cinder-dump: checks the visible recovered image (SHA-256 + runs
# it + captured output), then re-executes /app/solve.py on every hidden dumps
# directory and validates the same properties. Writes REWARD (0/1) to
# /logs/verifier/reward.txt. Never crashes on malformed agent output.
set -u
mkdir -p /logs/verifier

if [ ! -f /app/solve.py ]; then
  echo "missing /app/solve.py" >&2
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

python3 - <<'PY'
import hashlib, os, shutil, subprocess, sys, tempfile

FAIL = []


def check_image(bin_path, want_sha, want_out, label):
    if not os.path.isfile(bin_path):
        FAIL.append("%s: missing %s" % (label, bin_path))
        return
    try:
        data = open(bin_path, "rb").read()
    except Exception as e:
        FAIL.append("%s: unreadable image: %r" % (label, e))
        return
    if want_sha and hashlib.sha256(data).hexdigest() != want_sha.strip():
        FAIL.append("%s: sha256 mismatch" % label)
    if data[:4] != b"\x7fELF":
        FAIL.append("%s: not an ELF image" % label)
    # execute it (never let a bad image crash the verifier)
    tmp = tempfile.mkdtemp(prefix="cinder_run_")
    try:
        exe = os.path.join(tmp, "artifact")
        shutil.copyfile(bin_path, exe)
        os.chmod(exe, 0o755)
        r = subprocess.run([exe], capture_output=True, timeout=30)
        if r.returncode != 0:
            FAIL.append("%s: artifact exit=%d" % (label, r.returncode))
        if want_out and r.stdout.decode("utf-8", "replace") != want_out:
            FAIL.append("%s: artifact stdout mismatch" % label)
    except Exception as e:
        FAIL.append("%s: artifact run error: %r" % (label, e))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


# ---------- visible case ----------
want_sha = None
try:
    want_sha = open("/tests/expected_visible_sha.txt").read().strip()
except Exception:
    FAIL.append("visible sha fixture unreadable")
want_out = None
try:
    want_out = open("/tests/expected_visible_out.txt").read()
except Exception:
    FAIL.append("visible stdout fixture unreadable")
check_image("/app/recovered.bin", want_sha or "", want_out or "", "visible")
if os.path.isfile("/app/recovered_out.txt"):
    try:
        got = open("/app/recovered_out.txt", "rb").read().decode("utf-8", "replace")
        if want_out is not None and got != want_out:
            FAIL.append("visible: recovered_out.txt mismatch")
    except Exception as e:
        FAIL.append("visible: recovered_out.txt unreadable: %r" % e)
else:
    FAIL.append("visible: missing /app/recovered_out.txt")
if not os.path.isdir("/app/dumps") or not os.path.isfile("/app/dumps/manifest.txt"):
    FAIL.append("visible dumps fixture missing")

# ---------- hidden cases ----------
HID = "/tests/hidden"
if os.path.isdir(HID):
    cases = [c for c in sorted(os.listdir(HID))
             if os.path.isfile(os.path.join(HID, c, "expected_sha.txt"))]
    if not cases:
        FAIL.append("no hidden cases found")
    for c in cases:
        base = os.path.join(HID, c)
        out = tempfile.mkdtemp(prefix="cinder_hidden_")
        try:
            r = subprocess.run(
                [sys.executable, "/app/solve.py", os.path.join(base, ""),
                 os.path.join(out, "recovered.bin")],
                capture_output=True, text=True, timeout=120)
            if r.returncode != 0:
                FAIL.append("%s: solver exit=%d" % (c, r.returncode))
                continue
            want_sha = open(os.path.join(base, "expected_sha.txt")).read().strip()
            want_out = open(os.path.join(base, "expected_out.txt")).read()
            check_image(os.path.join(out, "recovered.bin"), want_sha, want_out, c)
        except Exception as e:
            FAIL.append("%s: verifier error: %r" % (c, e))
        finally:
            shutil.rmtree(out, ignore_errors=True)

print("verify failures:", FAIL)
with open("/logs/verifier/reward.txt", "w") as f:
    f.write("1" if not FAIL else "0")
sys.exit(0)
PY
