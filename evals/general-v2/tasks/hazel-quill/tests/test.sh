#!/bin/bash
# Verifier for hazel-quill: EXECUTES the deliverable /app/unquarantine.py on
# every hidden quarantine directory under /tests/hidden and re-checks the
# visible artifacts, against an independent reference decoder. ENFORCES the
# no-modify rule on /app/quarantine. Writes 1.0/0.0 to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_QUARANTINE_SHA="d821cc74c62619f23257f3ed1689905b932947547aa60862605f2280e2aa8cb4"

python3 - "$PRISTINE_QUARANTINE_SHA" <<'PY'
import base64, hashlib, os, shutil, subprocess, sys

SOLVE = "/app/unquarantine.py"
pristine_sha = sys.argv[1]

failures = []


def quarantine_sha(root):
    h = hashlib.sha256()
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isfile(p):
            return None
        h.update(name.encode())
        h.update(b"\x00")
        h.update(open(p, "rb").read())
        h.update(b"\x01")
    return h.hexdigest()


def reference_decode(segment):
    """Independent reference for the documented naming scheme."""
    if not segment:
        return None
    try:
        raw = base64.b64decode(segment, validate=True)
    except Exception:
        return None
    if not raw:
        return None
    try:
        name = raw.decode("utf-8")
    except UnicodeDecodeError:
        return None
    if not name or "/" in name or "\x00" in name or name in (".", ".."):
        return None
    return name


def reference_manifest(input_dir):
    """{original name: source path} for the valid files of a quarantine dir."""
    got = {}
    for entry in sorted(os.listdir(input_dir)):
        if not entry.endswith(".qtn"):
            continue
        full = os.path.join(input_dir, entry)
        if not os.path.isfile(full) or os.path.islink(full):
            continue
        name = reference_decode(entry[: -len(".qtn")])
        if name is not None:
            got[name] = full  # later processed files win
    return got


def check_run(input_dir, output_dir, tag):
    """Run the agent program on input_dir and compare with the reference."""
    if os.path.exists(output_dir):
        shutil.rmtree(output_dir)
    try:
        r = subprocess.run([sys.executable, SOLVE, input_dir, output_dir],
                           capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
        return "timed out"
    if r.returncode != 0:
        return "exit %d (expected 0)" % r.returncode

    want = reference_manifest(input_dir)
    rec = os.path.join(output_dir, "recovered.txt")
    if not os.path.isfile(rec):
        return "recovered.txt missing"
    try:
        with open(rec, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except Exception:
        return "recovered.txt unreadable"
    if lines and lines[-1] == "":
        lines = lines[:-1]
    else:
        return "recovered.txt must end with a final newline"
    if lines != sorted(want):
        return "manifest %r != expected %r" % (lines[:6], sorted(want)[:6])

    restored = os.path.join(output_dir, "restored")
    if not os.path.isdir(restored):
        return "restored/ missing"
    got_files = set()
    for dirpath, _dirs, files in os.walk(restored):
        for f in files:
            full = os.path.join(dirpath, f)
            got_files.add(os.path.relpath(full, restored))
    if got_files != set(want):
        return "restored set mismatch: extra=%s missing=%s" % (
            sorted(got_files - set(want))[:4], sorted(set(want) - got_files)[:4])
    for name, src in want.items():
        dst = os.path.join(restored, name)
        if open(src, "rb").read() != open(dst, "rb").read():
            return "restored %r bytes differ from source" % name
    return None


# ---- no-modify rule on the shipped quarantine -----------------------------
if not os.path.isdir("/app/quarantine"):
    failures.append("/app/quarantine missing")
else:
    cur = quarantine_sha("/app/quarantine")
    if cur != pristine_sha:
        failures.append("/app/quarantine was modified")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/unquarantine.py")
else:
    # ---- visible artifacts produced by the agent --------------------------
    err = check_run("/app/quarantine", "/tmp/hq_vis_recheck", "visible")
    if err:
        failures.append("visible re-run: %s" % err)
    if not os.path.isfile("/app/recovered.txt"):
        failures.append("missing /app/recovered.txt")
    else:
        want = sorted(reference_manifest("/app/quarantine"))
        try:
            with open("/app/recovered.txt", encoding="utf-8") as fh:
                lines = fh.read().split("\n")
            if lines and lines[-1] == "":
                lines = lines[:-1]
            if lines != want:
                failures.append("/app/recovered.txt != expected manifest")
        except Exception:
            failures.append("/app/recovered.txt unreadable")
    if not os.path.isdir("/app/restored"):
        failures.append("missing /app/restored")
    else:
        want = reference_manifest("/app/quarantine")
        for name, src in want.items():
            dst = os.path.join("/app/restored", name)
            if not (os.path.isfile(dst) and
                    open(src, "rb").read() == open(dst, "rb").read()):
                failures.append("/app/restored/%r wrong or missing" % name)
                break

    # ---- hidden cases ------------------------------------------------------
    hidden = "/tests/hidden"
    if not os.path.isdir(hidden) or not os.listdir(hidden):
        failures.append("no hidden cases present")
    for case in sorted(os.listdir(hidden)):
        qdir = os.path.join(hidden, case)
        if not os.path.isdir(qdir):
            failures.append("hidden '%s' is not a directory" % case)
            continue
        err = check_run(qdir, "/tmp/hq_hidden_" + case, case)
        if err:
            failures.append("hidden '%s': %s" % (case, err))

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
