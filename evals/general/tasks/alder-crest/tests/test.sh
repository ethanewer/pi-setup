#!/bin/bash
# Verifier for alder-crest: ENFORCES protected-file immutability on the shipped
# paper, EXECUTES /app/solve.py on the visible paper and on every hidden paper
# tree in /tests/hidden, and checks the compiled page / digests / deliverables.
# Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the PROTECTED shipped inputs in /app/press (the instruction
# forbids modifying them; tampering defeats the visible-case check).
PRISTINE_FRAME_SHA="61f3d5a0e7cb6bb44ae9db34ef253d80a91ce45f7ba7b28ae4a8d9521b744282"
PRISTINE_MAP_SHA="be2f7d04ac8757a9f21fd8047b13213d5ee7c943fb32bcb60408dd9eec53bf12"

no_modify_broken=0
for spec in "/app/press/frame.tex:$PRISTINE_FRAME_SHA" "/app/press/allowed.map:$PRISTINE_MAP_SHA"; do
    path="${spec%%:*}"; want="${spec##*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
    else
        actual="$(sha256sum "$path" | awk '{print $1}')"
        if [ "$actual" != "$want" ]; then
            echo "no-modify: $path was modified" >&2
            no_modify_broken=1
        fi
    fi
done

python3 - "$no_modify_broken" <<'PY'
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []

if no_modify_broken:
    failures.append("protected frame.tex/allowed.map modified or missing")


def sha_file(path):
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def run_case(press_dir, workdir):
    """Run the deliverable on press_dir; return (ok, report_or_None, compiled_path)."""
    compiled = os.path.join(workdir, "compiled.tex")
    report = os.path.join(workdir, "report.json")
    for p in (compiled, report):
        if os.path.exists(p):
            os.remove(p)
    # snapshot protected files to verify immutability across the run
    prot_before = {n: open(os.path.join(press_dir, n), "rb").read()
                   for n in ("frame.tex", "allowed.map")}
    r = subprocess.run(
        [sys.executable, SOLVE, press_dir, compiled, report],
        capture_output=True, text=True, timeout=120,
    )
    prot_after = {n: open(os.path.join(press_dir, n), "rb").read()
                  for n in ("frame.tex", "allowed.map")}
    if prot_before != prot_after:
        return False, None, None
    if r.returncode != 0 or not os.path.isfile(compiled) or not os.path.isfile(report):
        return False, None, None
    try:
        with open(report) as fh:
            rep = json.load(fh)
        with open(compiled, "rb") as fh:
            comp_bytes = fh.read()
    except Exception:
        return False, None, None
    if not isinstance(rep, dict) or set(rep.keys()) != {
        "edited_sha256", "compiled_sha256", "frame_sha256", "map_sha256",
        "replacements",
    }:
        return False, None, None
    if rep["compiled_sha256"] != hashlib.sha256(comp_bytes).hexdigest():
        return False, None, None
    return True, rep, comp_bytes


def check_against_expected(rep, comp_bytes, expected_path):
    try:
        with open(expected_path) as fh:
            want = json.load(fh)
    except Exception:
        return False
    return (rep.get("edited_sha256") == want.get("edited_sha256")
            and rep.get("compiled_sha256") == want.get("compiled_sha256")
            and hashlib.sha256(comp_bytes).hexdigest() == want.get("compiled_sha256")
            and rep.get("replacements") == want.get("replacements")
            and rep.get("frame_sha256") == want.get("frame_sha256")
            and rep.get("map_sha256") == want.get("map_sha256"))


if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # --- visible case: EXECUTE solve.py on the shipped paper ---
    ok, rep, comp = run_case("/app/press", tempfile.mkdtemp(prefix="vis_"))
    if not ok:
        failures.append("visible case failed (crash, bad report, or protected files touched)")
    elif not check_against_expected(rep, comp, "/tests/expected.json"):
        failures.append("visible case output mismatch")

    # --- visible deliverables ---
    if os.path.isfile("/app/compiled.tex"):
        try:
            with open("/tests/expected.json") as fh:
                want = json.load(fh)
            if sha_file("/app/compiled.tex") != want.get("compiled_sha256"):
                failures.append("/app/compiled.tex does not match expected compiled page")
        except Exception:
            failures.append("/app/compiled.tex unreadable")
    else:
        failures.append("missing /app/compiled.tex")

    if os.path.isfile("/app/answer.json"):
        try:
            with open("/app/answer.json") as fh:
                got = json.load(fh)
            with open("/tests/expected.json") as fh:
                want = json.load(fh)
            if got != want:
                failures.append("/app/answer.json does not match expected report")
        except Exception:
            failures.append("/app/answer.json unreadable")
    else:
        failures.append("missing /app/answer.json")

    # --- hidden cases: fresh paper trees with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            press = os.path.join(base, "press")
            exp = os.path.join(base, "expected.json")
            if not (os.path.isdir(press) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            # work on a copy so the pristine hidden fixture is never touched
            work = tempfile.mkdtemp(prefix="hid_")
            press_copy = os.path.join(work, "press")
            shutil.copytree(press, press_copy)
            ok, rep, comp = run_case(press_copy, work)
            if not ok:
                failures.append("hidden case '%s' failed (crash, bad report, or protected files touched)" % c)
            elif not check_against_expected(rep, comp, exp):
                failures.append("hidden case '%s' output mismatch" % c)
            shutil.rmtree(work, ignore_errors=True)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
