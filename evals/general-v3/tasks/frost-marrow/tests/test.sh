#!/bin/bash
# Verifier for frost-marrow: ENFORCES the no-modify rule on /app/artifacts,
# EXECUTES the deliverable /app/forge.py on the visible artifact directory and
# on every hidden artifact directory, and compares against guarded reference
# payloads. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib
import json
import os
import subprocess
import sys

FORGER = "/app/forge.py"

# Pristine sha256 of the supplied artifacts (agent must not modify them).
PRISTINE = {
    "ledger.csv": "e5db94a900a495159f0b27a5521b52e308706c2a195a0e17806f6ad9b9ff2400",
    "notes.log": "f40aef1695cffe375b1068af679b96fcbb29b09af461ac717c364a00327fb1bc",
    "pricebook.tsv": "7d7283439e20ab7f5d8b16702bb87d87086429daeb47e4930e28623161d9bf3a",
    "README.txt": "0322cdda6fbfa4edd7b3c7d0a0180a94ada3bb08b84ec00c182852eb85f5526c",
    "serial.txt": "45c5f3c9673d8b153d52fe82ebb475e23de6d7e82ffec909b9e9b8f51100073b",
    ".gitkeep": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
}

failures = []

# --- no-modify check on the supplied artifacts ---
artdir = "/app/artifacts"
if not os.path.isdir(artdir):
    failures.append("no-modify: /app/artifacts missing")
else:
    for name, want in PRISTINE.items():
        p = os.path.join(artdir, name)
        if not os.path.isfile(p):
            failures.append("no-modify: artifact %s missing" % name)
            continue
        with open(p, "rb") as fh:
            got = hashlib.sha256(fh.read()).hexdigest()
        if got != want:
            failures.append("no-modify: artifact %s was modified" % name)
    for entry in os.listdir(artdir):
        if entry not in PRISTINE:
            failures.append("no-modify: unexpected file %s in /app/artifacts" % entry)


def run_forger(artifact_dir, outfile):
    if os.path.exists(outfile):
        os.remove(outfile)
    return subprocess.run(
        [sys.executable, FORGER, artifact_dir, outfile],
        capture_output=True, text=True, timeout=120,
    )


def read_text(path):
    try:
        with open(path) as fh:
            return fh.read()
    except OSError:
        return None


if not os.path.isfile(FORGER):
    failures.append("missing /app/forge.py")
else:
    # ---------- visible case ----------
    tmp_out = "/tmp/frost_marrow_visible_out.txt"
    r = run_forger(artdir, tmp_out)
    expected = None
    try:
        with open("/tests/expected.json") as fh:
            expected = json.load(fh).get("payload")
    except Exception:
        failures.append("visible expected.json unreadable")
    if expected is not None:
        if r.returncode != 0:
            failures.append("visible case: exited %d (%s)"
                            % (r.returncode, r.stderr.strip()[:200]))
        else:
            if r.stdout.strip() != expected:
                failures.append("visible case: stdout %r, want %r"
                                % (r.stdout.strip(), expected))
            got_file = read_text(tmp_out)
            if got_file is None:
                failures.append("visible case: outfile not created")
            elif got_file.strip() != expected:
                failures.append("visible case: outfile %r, want %r"
                                % (got_file.strip(), expected))
        # answer.txt deliverable for the visible inputs
        got_answer = read_text("/app/answer.txt")
        if got_answer is None:
            failures.append("missing /app/answer.txt")
        elif got_answer.strip() != expected:
            failures.append("answer.txt %r, want %r"
                            % (got_answer.strip(), expected))

    # ---------- hidden cases ----------
    hidden_dir = "/tests/hidden"
    if not os.path.isdir(hidden_dir):
        failures.append("no hidden cases present")
    else:
        for case in sorted(os.listdir(hidden_dir)):
            base = os.path.join(hidden_dir, case)
            case_art = os.path.join(base, "artifacts")
            if not os.path.isdir(case_art):
                failures.append("hidden '%s': no artifacts dir" % case)
                continue
            expect_fail = os.path.isfile(os.path.join(base, "expect_fail"))
            tmp_out = "/tmp/frost_marrow_hidden_out.txt"
            r = run_forger(case_art, tmp_out)
            if expect_fail:
                if r.returncode == 0:
                    failures.append("hidden '%s': expected non-zero exit" % case)
                if r.stdout.strip():
                    failures.append("hidden '%s': expected empty stdout" % case)
                if os.path.exists(tmp_out):
                    failures.append("hidden '%s': outfile must not be created" % case)
                continue
            want = read_text(os.path.join(base, "expected.txt"))
            if want is None:
                failures.append("hidden '%s': missing expected.txt" % case)
                continue
            want = want.strip()
            if r.returncode != 0:
                failures.append("hidden '%s': exited %d (%s)"
                                % (case, r.returncode, r.stderr.strip()[:200]))
            elif r.stdout.strip() != want:
                failures.append("hidden '%s': stdout %r, want %r"
                                % (case, r.stdout.strip(), want))
            else:
                got_file = read_text(tmp_out)
                if got_file is None or got_file.strip() != want:
                    failures.append("hidden '%s': outfile mismatch" % case)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
