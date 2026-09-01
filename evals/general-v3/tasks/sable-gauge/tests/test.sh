#!/bin/bash
# Verifier for sable-gauge: EXECUTES the deliverable /app/pack.py on the visible
# seed tree and on every hidden tree in /tests/hidden, byte-compares the
# produced tar archives against the expected reproducible archives, and checks
# the identity digest files. Also byte-checks the visible deliverables
# /app/bundle.tar and /app/bundle.sha256. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib, os, subprocess, sys

PACK = "/app/pack.py"
failures = []


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def read_digest(path):
    with open(path, "rb") as fh:
        return fh.read()


def run_case(tree, expected_tar, tag):
    out_tar = "/tmp/sable_gauge_%s.tar" % tag.replace("/", "_")
    out_digest = out_tar + ".sha"
    for p in (out_tar, out_digest):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run(
            [sys.executable, PACK, tree, out_tar, out_digest],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as exc:
        failures.append("%s: packer crashed: %s" % (tag, exc))
        return
    if r.returncode != 0:
        failures.append("%s: packer exited %d" % (tag, r.returncode))
        return
    if not os.path.isfile(out_tar) or not os.path.isfile(out_digest):
        failures.append("%s: packer produced no output" % tag)
        return
    if open(out_tar, "rb").read() != open(expected_tar, "rb").read():
        failures.append("%s: archive bytes differ from expected reproducible archive" % tag)
    want = sha256_file(expected_tar).encode() + b"\n"
    if read_digest(out_digest) != want:
        failures.append("%s: digest file wrong (must be lowercase hex sha256 of the tar + one newline)" % tag)


if not os.path.isfile(PACK):
    failures.append("missing /app/pack.py")
else:
    # visible case: EXECUTE the deliverable on the shipped seed tree
    if os.path.isdir("/app/seed_tree"):
        run_case("/app/seed_tree", "/tests/expected_seed.tar", "visible-run")
    else:
        failures.append("visible /app/seed_tree missing")

    # visible-case deliverables: /app/bundle.tar and /app/bundle.sha256
    if os.path.isfile("/app/bundle.tar"):
        if open("/app/bundle.tar", "rb").read() != open("/tests/expected_seed.tar", "rb").read():
            failures.append("/app/bundle.tar differs from the expected reproducible archive")
    else:
        failures.append("missing /app/bundle.tar")
    if os.path.isfile("/app/bundle.sha256"):
        want = sha256_file("/tests/expected_seed.tar").encode() + b"\n"
        if read_digest("/app/bundle.sha256") != want:
            failures.append("/app/bundle.sha256 wrong (lowercase hex sha256 of bundle.tar + one newline)")
    else:
        failures.append("missing /app/bundle.sha256")

    # hidden cases: unicode/case-collation traps, empty files/dirs, nesting
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            tree = os.path.join(base, "tree")
            expected = os.path.join(base, "expected.tar")
            if not (os.path.isdir(tree) and os.path.isfile(expected)):
                failures.append("hidden case '%s' malformed" % c)
                continue
            run_case(tree, expected, "hidden:%s" % c)
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
