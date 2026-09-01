#!/bin/bash
# Verifier for sorrel-tide: EXECUTES the deliverable solver (/app/solve.py) on
# the visible generator and on every hidden generator under /tests/hidden, and
# re-derives the expected candidate list + vault selection independently from
# each module. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier

python3 - <<'PY'
import hashlib
import importlib.util
import json
import os
import subprocess
import sys
from collections import Counter

SOLVE = "/app/solve.py"
failures = []


def load_generator(path):
    spec = importlib.util.spec_from_file_location("gen_%s" % abs(hash(path)), path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def rederive(gen_path):
    """Independently re-derive expected candidates and selection from a module."""
    gen = load_generator(gen_path)
    entries = []
    for serial in range(gen.SERIAL_HI):
        if not gen.activated(serial):
            continue
        token = gen.emit_keycard(serial)
        if gen.is_well_formed(token):
            entries.append((serial, token))
    entries.sort(key=lambda e: e[0])
    matches = []
    for serial, token in entries:
        digest = hashlib.sha256(token.encode("utf-8")).hexdigest()
        if int(digest, 16) % gen.VAULT_MODULUS == gen.VAULT_PIN:
            matches.append((serial, token))
    return gen, entries, matches


def check_run(gen_path, label):
    out_c = "/tmp/st_cand_%s.txt" % label
    out_a = "/tmp/st_ans_%s.json" % label
    for p in (out_c, out_a):
        if os.path.exists(p):
            os.remove(p)
    try:
        r = subprocess.run(["python3", SOLVE, gen_path, out_c, out_a],
                           capture_output=True, text=True, timeout=120)
    except Exception as e:
        failures.append("%s: solver crashed: %r" % (label, e))
        return
    if r.returncode != 0:
        failures.append("%s: solver exited %d: %s" % (label, r.returncode, r.stderr[-300:]))
        return
    gen, entries, matches = rederive(gen_path)
    if len(matches) != 1:
        failures.append("%s: internal: expected module yields %d matches" % (label, len(matches)))
        return
    want_tokens = [t for _s, t in entries]

    # candidates file: exact content, one token per line, ascending serial order
    try:
        with open(out_c) as fh:
            got_lines = [ln.rstrip("\n") for ln in fh if ln.strip() != ""]
    except Exception as e:
        failures.append("%s: candidates file unreadable: %r" % (label, e))
        return
    if got_lines != want_tokens:
        if len(got_lines) != len(want_tokens):
            failures.append("%s: candidate_count %d != expected %d"
                            % (label, len(got_lines), len(want_tokens)))
        else:
            bad = [i for i, (a, b) in enumerate(zip(got_lines, want_tokens)) if a != b][:3]
            failures.append("%s: candidates.txt differs at lines %s (wrong order or wrong set)"
                            % (label, bad))

    # answer json
    try:
        with open(out_a) as fh:
            ans = json.load(fh)
    except Exception as e:
        failures.append("%s: answer json unreadable: %r" % (label, e))
        return
    if not isinstance(ans, dict):
        failures.append("%s: answer json is not an object" % label)
        return
    serial, token = matches[0]
    expect = {
        "keycard": token,
        "active_serial": int(serial),
        "candidate_count": len(entries),
        "pin": int(gen.VAULT_PIN),
        "modulus": int(gen.VAULT_MODULUS),
    }
    if set(ans.keys()) != set(expect.keys()):
        failures.append("%s: answer keys %r != %r" % (label, sorted(ans.keys()), sorted(expect.keys())))
        return
    for k, v in expect.items():
        if ans.get(k) != v:
            failures.append("%s: answer[%s]=%r != %r" % (label, k, ans.get(k), v))


# --- deliverables present ---------------------------------------------------
for d in ["/app/solve.py", "/app/candidates.txt", "/app/answer.json"]:
    if not os.path.isfile(d):
        failures.append("missing deliverable %s" % d)
if not failures:
    # visible generator module intact?
    try:
        rederive("/app/keycard_gen.py")
    except Exception as e:
        failures.append("/app/keycard_gen.py missing or broken: %r" % (e,))

if not failures:
    # --- visible case ---
    check_run("/app/keycard_gen.py", "visible")

    # visible deliverables must match the expected visible derivation
    gen, entries, matches = rederive("/app/keycard_gen.py")
    try:
        with open("/app/candidates.txt") as fh:
            got = [ln.rstrip("\n") for ln in fh if ln.strip()]
        if got != [t for _s, t in entries]:
            failures.append("/app/candidates.txt does not match the visible derivation")
    except Exception as e:
        failures.append("/app/candidates.txt unreadable: %r" % (e,))
    try:
        with open("/app/answer.json") as fh:
            ans = json.load(fh)
        serial, token = matches[0]
        if (ans.get("keycard") != token or ans.get("active_serial") != int(serial)
                or ans.get("candidate_count") != len(entries)
                or ans.get("pin") != int(gen.VAULT_PIN)
                or ans.get("modulus") != int(gen.VAULT_MODULUS)):
            failures.append("/app/answer.json does not match the visible derivation")
    except Exception as e:
        failures.append("/app/answer.json unreadable: %r" % (e,))

    # --- hidden cases: fresh generator modules with different constants ---
    hidden_dir = "/tests/hidden"
    cases = []
    if os.path.isdir(hidden_dir):
        for d in sorted(os.listdir(hidden_dir)):
            p = os.path.join(hidden_dir, d, "keycard_gen.py")
            if os.path.isfile(p):
                cases.append((d, p))
    if not cases:
        failures.append("no hidden generator cases found")
    for name, path in cases:
        check_run(path, name)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

rc=$?
if [ "$rc" -eq 0 ]; then reward=1; else reward=0; fi
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0
