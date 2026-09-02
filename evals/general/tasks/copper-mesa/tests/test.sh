#!/bin/bash
# Verifier for copper-mesa: checks the visible deliverables, ENFORCES the
# no-modify rule on the shipped /app/data dataset, and EXECUTES
# /app/pick_top.py on the visible dataset and on every hidden dataset under
# /tests/hidden, comparing the emitted line to the reference winner. Writes
# REWARD (0/1) to /logs/verifier/reward.txt. Never crashes on malformed or
# missing agent output.
set -u

mkdir -p /logs/verifier
reward=0

python3 - <<'PY'
import hashlib, json, os, subprocess, sys

SOLVE = "/app/pick_top.py"
VISIBLE = "/app/data/results"
REPORT = "/app/leaderboard_top.txt"
no_modify_broken = False

PRISTINE = PRISTINE = {
    "atlas-run/code.json": "7571a06de6e345e35134ac284b14be40e4c72507564ef8f0ab5ef3043c219e94",
    "atlas-run/facts.json": "7c92e8de1e5a44894f0df237405ad2a64d92134bd064e9a43b8930611b858eb7",
    "atlas-run/math.json": "c82704df96b3923cddfecece892ead9e3a12581e01c94fcb0af62c0eca51a56b",
    "atlas-run/meta.json": "e8869caaa2470d46cf12e63d17f9ab91ac547d9bd6241cc1f36f4ffe568e84bb",
    "m3/code.json": "2407e7e0ae48cbc38dc3722ee23587206370f3a7a594d3083af7ad2f13a3a0fb",
    "m3/facts.json": "003ac0f0a5bc6fd8e3ede8e59276e7791285bb5ea1552f1b85c67b3ae950138d",
    "m3/math.json": "122d6a2d0a6d6df3150f8224e24e3951638046a3ead9ec08a114caab3fd12323",
    "m3/meta.json": "ff19062560696c82b884042321100f2a81e85c4da2bd1a2adadf8bfe30351234",
    "m4/code.json": "7b6f2fea5914cc2b4f50946799076be7519f9899c9b9eabb2d73b1c4bad186d1",
    "m4/math.json": "bff3093046af3257bc924ca28dabbafe8438e12b35a1ebc16338a6be49720427",
    "m4/meta.json": "70878dd545421473fb3c42ee4f2ff89b1eaa83fd1efc9597217b7903c456c88f",
    "m5/code.json": "190e25ed4b3274a26550301425d1d1dd41436347fed08b472183d5997f31161a",
    "m5/math.json": "87d2ae94a0bc32a37d8cae52bc786c0d7ad04d318fe9cd04b512e722f0ef325d",
    "m5/meta.json": "076fbe4ea0005158b3e592b433dee592d933d14f0d770a85df60f5eb2b237a06",
    "m6/code.json": "dc2afe6bd4e3caa5090213fd445b2c78c76cd836b7fda591c4cde73bc52ceb22",
    "m6/facts.json": "b08b5c5bb21106b14d3cb5218a4f4fd12e069298d2f6743784481bc6d5909e84",
    "m6/math.json": "7751802daffc2948a05f61bb211d51c6d49e1419bc941bebafcfaa3a9aa3a41b",
    "m6/meta.json": "2dcd3a5aa330cd2232797cf7c7d6718b845d2d2ae1303ae8f73f044dadc20200",
    "m7/math.json": "439c26e134f278bdced4957b77540ac683947ab4b19e418af73820561dd236e1",
    "m7/meta.json": "ffc799845c54fc4884aaac277f9f93847b59358fd1ae7c613ca32d420223933b",
    "m8/math.json": "b8b87e7b6328093958f16d978a08419e50d5bdb65e03863fda23270cbe1ebe66",
    "m8/meta.json": "be302461cda285db3ed2d45fb767b23e08ca8808b35a638009937df22b332d73",
    "stray.json": "96ba9ef05428291286f47380e9b7a1549aa250644dcea86a4f6ee46c4fe0791d",
    "zen-run-a/code.json": "22f1e2b1e524da7beb7f7e2755d544640f7365a5d95e4e36a66e1fe39c4ae61f",
    "zen-run-a/math.json": "48389d98c8e6f658a16611f0cf5489bc249ec8b3bb283fdba1e72059e1f9d3fa",
    "zen-run-a/meta.json": "c58464ae4c37a921a810f3df1393b1f1f7b92231ad5ddf6efef363c125583020",
    "zen-run-b/facts.json": "bfb5dc8182b88f51f681723e07e02bdae563c799fa7221ba39399fea113054b6",
    "zen-run-b/meta.json": "09a538f002c735dfe042a6c827b7f7aa6cb5cc0fdbe0054c373cf7e917be14fa",
    "zen-run-b/summary.json": "326f68ca1f315662e848fec28e3c6616f6e345afe79b116542efc5daf708ebb6",
}

for rel, want_sha in PRISTINE.items():
    p = os.path.join(VISIBLE, rel)
    if not os.path.isfile(p):
        print("no-modify: missing %s" % rel, file=sys.stderr)
        no_modify_broken = True
        continue
    h = hashlib.sha256(open(p, "rb").read()).hexdigest()
    if h != want_sha:
        print("no-modify: %s was modified" % rel, file=sys.stderr)
        no_modify_broken = True


def run_case(results_dir, expected_path):
    out = "/tmp/copper_mesa_out.txt"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run([sys.executable, SOLVE, results_dir, out],
                           capture_output=True, text=True, timeout=60)
    except Exception:
        return False
    if r.returncode != 0 or not os.path.exists(out):
        return False
    try:
        with open(out) as fh:
            content = fh.read()
        with open(expected_path) as fh:
            want = fh.read()
    except Exception:
        return False
    lines = content.strip().splitlines()
    if len(lines) != 1:
        return False
    return lines[0].strip() == want.strip()


failures = []
if no_modify_broken:
    failures.append("shipped dataset modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/pick_top.py")
else:
    # --- visible dataset: EXECUTE the picker on the shipped inputs ---
    if not (os.path.isdir(VISIBLE) and os.path.isfile("/tests/expected.txt")):
        failures.append("visible dataset files missing")
    elif not run_case(VISIBLE, "/tests/expected.txt"):
        failures.append("visible case failed")

    # --- visible deliverable: /app/leaderboard_top.txt ---
    if not os.path.isfile(REPORT):
        failures.append("missing /app/leaderboard_top.txt")
    else:
        try:
            content = open(REPORT).read()
            want = open("/tests/expected.txt").read().strip()
            lines = content.strip().splitlines()
            if len(lines) != 1 or lines[0].strip() != want:
                failures.append("leaderboard_top.txt is not the single "
                                "correct trimmed line")
        except Exception:
            failures.append("leaderboard_top.txt unreadable")

    # --- hidden datasets ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(d for d in os.listdir(hidden_dir)
                       if os.path.isdir(os.path.join(hidden_dir, d)))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            res = os.path.join(base, "results")
            exp = os.path.join(base, "expected.txt")
            if not (os.path.isdir(res) and os.path.isfile(exp)):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(res, exp):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
