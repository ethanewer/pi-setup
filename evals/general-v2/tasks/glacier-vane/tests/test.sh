#!/bin/bash
# Verifier for glacier-vane: checks the deliverables are present and correct,
# ENFORCES the no-modify rule on the supplied /app fixtures, and EXECUTES the
# deliverable client (/app/spectra_client.py) on the visible case and on every
# hidden case in /tests/hidden. Writes REWARD (0/1) to /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

# Pristine sha256 of the supplied visible fixtures in /app (the instruction
# tells the agent not to modify these; tampering defeats the visible check).
PRISTINE_SERVER_SHA="e8cdbf973ca5b0bfa89fcfbaf7feb26a3f3b84bf08f0d02c875a054d2a059291"
PRISTINE_PROTEINS_SHA="7c8db7b1d911813844ca9399a9a2bdff62c2042777bfcef6f9cb0f23da099f26"
PRISTINE_CHANNELS_SHA="af1bbd0820ba8e30c064881ee7316394096bcab8f556386730a3e429855da5a9"

no_modify_broken=0
for pair in \
    "/app/api_server.py:$PRISTINE_SERVER_SHA" \
    "/app/data/proteins.json:$PRISTINE_PROTEINS_SHA" \
    "/app/data/channels.json:$PRISTINE_CHANNELS_SHA"; do
    path="${pair%%:*}"
    want="${pair#*:}"
    if [ ! -f "$path" ]; then
        echo "no-modify: $path missing" >&2
        no_modify_broken=1
        continue
    fi
    actual="$(sha256sum "$path" | awk '{print $1}')"
    if [ "$actual" != "$want" ]; then
        echo "no-modify: $path was modified" >&2
        no_modify_broken=1
    fi
done

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

CLIENT = "/app/spectra_client.py"
no_modify_broken = int(sys.argv[1])
failures = []


def norm(obj):
    """Normalize a report so ints/floats compare cleanly."""
    assert isinstance(obj, dict), obj
    assert set(obj.keys()) == {"channels", "unassigned_channels"}, obj.keys()
    channels = obj["channels"]
    unassigned = obj["unassigned_channels"]
    assert isinstance(channels, dict) and isinstance(unassigned, list)
    out = {}
    for name, payload in channels.items():
        assert set(payload.keys()) == {
            "protein_id", "excitation_nm", "emission_nm", "brightness"}, payload
        out[name] = (str(payload["protein_id"]),
                     round(float(payload["excitation_nm"]), 4),
                     round(float(payload["emission_nm"]), 4),
                     round(float(payload["brightness"]), 4))
    return out, sorted(str(u) for u in unassigned)


def run_case(data_dir, expected_path, out_path):
    if os.path.exists(out_path):
        os.remove(out_path)
    try:
        r = subprocess.run(
            [sys.executable, CLIENT, data_dir, out_path],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return False
    if r.returncode != 0 or not os.path.exists(out_path):
        return False
    try:
        with open(out_path) as f:
            got = json.load(f)
        with open(expected_path) as f:
            want = json.load(f)
        return norm(got) == norm(want)
    except Exception:
        return False


if no_modify_broken:
    failures.append("visible fixtures modified or missing (no-modify rule)")

if not os.path.isfile(CLIENT):
    failures.append("missing /app/spectra_client.py")
else:
    # --- visible case: EXECUTE the client on the live supplied fixtures ---
    if not run_case("/app/data", "/tests/expected.json",
                    "/tmp/glacier_vane_visible.json"):
        failures.append("visible case failed")

    # --- visible-case deliverable: /app/spectra_report.json must match ---
    if os.path.isfile("/app/spectra_report.json"):
        try:
            with open("/app/spectra_report.json") as f:
                got = json.load(f)
            with open("/tests/expected.json") as f:
                want = json.load(f)
            if norm(got) != norm(want):
                failures.append("spectra_report.json does not match visible expected")
        except Exception:
            failures.append("spectra_report.json unreadable")
    else:
        failures.append("missing /app/spectra_report.json")

    # --- hidden cases: fresh databases + channel specs with their own expecteds ---
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            base = os.path.join(hidden_dir, c)
            data = os.path.join(base, "data")
            exp = os.path.join(base, "expected.json")
            if not os.path.isdir(data) or not os.path.isfile(exp):
                failures.append("hidden '%s' malformed" % c)
                continue
            if not run_case(data, exp, "/tmp/glacier_vane_hidden_out.json"):
                failures.append("hidden case '%s' failed" % c)

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
