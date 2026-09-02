#!/bin/bash
# Verifier for vellum-notch: checks the visible-case deliverables, enforces the
# integrity of the live coexisting audit log, rejects any extracted/sensitive
# leftovers under /app, and EXECUTES the deliverable script (/app/extract_
# member.sh) on hidden archives in scratch dirs requiring zero disk writes.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied live log (the instruction says it must not
# be touched; a full extraction would clobber it with the archive's stale copy).
PRISTINE_AUDIT_SHA="b34f56ba1fcdb5730c90ce8e43d96f0071b0b7f625ee07ba98af86070a441b5b"

audit_ok=1
if [ ! -f /app/ir/audit.log ]; then
    echo "integrity: /app/ir/audit.log missing" >&2
    audit_ok=0
else
    actual="$(sha256sum /app/ir/audit.log | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_AUDIT_SHA" ]; then
        echo "integrity: /app/ir/audit.log was modified or clobbered" >&2
        audit_ok=0
    fi
fi

python3 - "$audit_ok" <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tarfile
import tempfile

AUDIT_OK = int(sys.argv[1])

SCRIPT = "/app/extract_member.sh"
VISIBLE_ARCHIVE = "/app/ir/incident.tar.gz"
VISIBLE_MEMBER = "manifests/build.id"
VISIBLE_OUT = "/app/out/build.id"
VISIBLE_MEMBER_BYTES = b"BUILD_ID=ir-2087-3f8a12c4\nCHANNEL=stable\nBUILT=2032-03-14T09:26:00Z\n"

failures = []
if AUDIT_OK != 1:
    failures.append("live /app/ir/audit.log missing, modified or clobbered")

# the script deliverable must be executable as-is
if not os.path.isfile(SCRIPT):
    failures.append("missing /app/extract_member.sh")
else:
    if not os.access(SCRIPT, os.X_OK):
        failures.append("/app/extract_member.sh is not executable")


def run_script(archive, member, cwd):
    return subprocess.run([SCRIPT, archive, member], cwd=cwd,
                          capture_output=True, timeout=120)


def sensitive_leftovers(root):
    """Forbidden extracted artefacts under `root` (sensitive payloads or the
    archived audit.log that would clobber the live log)."""
    bad_names = {"creds", "heap", "triage", "manifests", "notes",
                 "cloud_tokens.env", "core.hex", "audit.log"}
    hits = []
    for dirpath, dirnames, filenames in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        for n in list(dirnames) + filenames:
            if n in bad_names and rel != ".":
                hits.append(os.path.join(dirpath, n))
            elif n in ("creds", "heap", "audit.log", "core.hex") and rel == ".":
                hits.append(os.path.join(dirpath, n))
    return hits


if os.path.isfile(SCRIPT) and os.access(SCRIPT, os.X_OK):
    # ---- visible case: script output must be the wanted member's bytes ----
    try:
        with tarfile.open(VISIBLE_ARCHIVE, "r:gz") as tf:
            expected = tf.extractfile(VISIBLE_MEMBER).read()
    except Exception as exc:
        expected = None
        failures.append("cannot read visible archive: %r" % exc)

    if expected is not None:
        if expected != VISIBLE_MEMBER_BYTES:
            failures.append("visible fixture drifted from contract")
        try:
            r = run_script(VISIBLE_ARCHIVE, VISIBLE_MEMBER, "/app")
            if r.returncode != 0:
                failures.append("script exited %d on visible archive" % r.returncode)
            if r.stdout != expected:
                failures.append("script stdout is not the member's raw bytes")
        except Exception as exc:
            failures.append("script run crashed: %r" % exc)

        # ---- deliverable 2: /app/out/build.id content ----
        if not os.path.isfile(VISIBLE_OUT):
            failures.append("missing /app/out/build.id")
        else:
            with open(VISIBLE_OUT, "rb") as fh:
                if fh.read() != expected:
                    failures.append("/app/out/build.id has wrong bytes")

    # ---- no extraction leftovers anywhere under /app ----
    if AUDIT_OK == 1:
        live_log = os.path.join("/app/ir", "audit.log")
        for hit in sensitive_leftovers("/app"):
            if os.path.abspath(hit) != live_log:
                failures.append("extracted leftover on disk: %s" % hit)
        if os.path.isdir("/app/ir"):
            extra = sorted(set(os.listdir("/app/ir")) -
                           {"incident.tar.gz", "audit.log"})
            if extra:
                failures.append("unexpected files materialized in /app/ir: %s"
                                % extra)

    # ---- hidden cases: scratch dir, sentinel log, zero disk writes ----
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            meta_path = os.path.join(base, "meta.json")
            exp_path = os.path.join(base, "expected.bin")
            arc_path = os.path.join(base, "archive.tar.gz")
            sentinel_path = os.path.join(base, "audit.log")
            if not all(os.path.isfile(p) for p in
                       (meta_path, exp_path, arc_path, sentinel_path)):
                failures.append("hidden '%s' malformed" % c)
                continue
            try:
                with open(meta_path) as fh:
                    member = json.load(fh)["member"]
                with open(exp_path, "rb") as fh:
                    expected = fh.read()
                with open(sentinel_path, "rb") as fh:
                    sentinel = fh.read()
                with open(arc_path, "rb") as fh:
                    arc_sha = hashlib.sha256(fh.read()).hexdigest()
            except Exception:
                failures.append("hidden '%s' unreadable fixtures" % c)
                continue

            scratch = tempfile.mkdtemp(prefix="vn-")
            try:
                s_arc = os.path.join(scratch, "archive.tar.gz")
                s_log = os.path.join(scratch, "audit.log")
                shutil.copyfile(arc_path, s_arc)
                shutil.copyfile(sentinel_path, s_log)
                r = run_script(s_arc, member, scratch)
                if r.returncode != 0:
                    failures.append("hidden '%s': script exited %d"
                                    % (c, r.returncode))
                if r.stdout != expected:
                    failures.append("hidden '%s': wrong bytes on stdout" % c)
                with open(s_log, "rb") as fh:
                    if fh.read() != sentinel:
                        failures.append("hidden '%s': sentinel log clobbered" % c)
                with open(s_arc, "rb") as fh:
                    if hashlib.sha256(fh.read()).hexdigest() != arc_sha:
                        failures.append("hidden '%s': archive was modified" % c)
                leftovers = set(os.listdir(scratch)) - {"archive.tar.gz",
                                                        "audit.log"}
                if leftovers:
                    failures.append("hidden '%s': full extraction leaked "
                                    "files: %s" % (c, sorted(leftovers)))
            except Exception as exc:
                failures.append("hidden '%s' crashed: %r" % (c, exc))
            finally:
                shutil.rmtree(scratch, ignore_errors=True)
    else:
        failures.append("missing /tests/hidden")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
