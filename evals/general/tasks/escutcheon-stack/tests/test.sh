#!/usr/bin/env bash
# Verifier for escutcheon-stack (executes-deliverable).
#
# Re-runs the agent's deliverable /app/stack/deploy.sh against the shipped
# live files and against three hidden snapshots, then independently checks:
#   (1) the deliverable exists and is executable,
#   (2) deploy.sh exits 0 on a fresh snapshot,
#   (3) no hand-managed live file was destroyed or rewritten (byte-identical),
#   (4) the second managed resource deployment.manifest has the exact content,
#   (5) `terraform plan` is empty after adoption,
#   (6) terraform.tfstate records exactly the adopted files plus the manifest.
# Writes numeric reward to /logs/verifier/reward.txt (1 = all pass, 0 = any fail).
#
# Guarantee a reward on every exit path: without the trap, a verifier that
# raises while inspecting the deliverable writes nothing and cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT
set -u
mkdir -p /logs/verifier

H=/tests/hidden
DELIV=/app/stack/deploy.sh
FAIL=false
failadd(){ echo "FAIL: $1"; FAIL=true; }

if [ ! -x "$DELIV" ]; then
  echo "deliverable $DELIV missing or not executable"
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

# --- per-case check in python: integrity, manifest, plan-empty, state ---
check_case() {
  python3 - "$1" "$2" <<'PY'
import hashlib, json, os, subprocess, sys
work, pristine = sys.argv[1], sys.argv[2]
fails = []

def f(msg): fails.append(msg)

# gather pristine live files
live_files = []
for name in sorted(os.listdir(pristine)):
    p = os.path.join(pristine, name)
    if os.path.isfile(p): live_files.append(name)

# (3) integrity: every pristine file present and byte-identical
for name in sorted(os.listdir(pristine)):
    p = os.path.join(pristine, name)
    if not os.path.isfile(p): continue
    got = os.path.join(work, "live", name)
    if not os.path.isfile(got):
        f("live file %s deleted during adoption" % name); continue
    with open(p, "rb") as a, open(got, "rb") as b:
        if a.read() != b.read():
            f("live file %s was rewritten (content changed) during adoption" % name)

# (4) manifest content == sorted live names joined by newline, no trailing newline
expected_manifest = "\n".join(sorted(live_files))
mp = os.path.join(work, "deployment.manifest")
if not os.path.isfile(mp):
    f("second managed resource deployment.manifest missing")
else:
    with open(mp) as fh:
        got_manifest = fh.read()
    if got_manifest != expected_manifest:
        f("deployment.manifest wrong: expected %r got %r" % (expected_manifest, got_manifest))

# (5) terraform plan must be empty (exit 0 == no changes) after adoption
plan = subprocess.run(
    ["terraform", "plan", "-detailed-exitcode", "-input=false", "-no-color"],
    cwd=work, capture_output=True, text=True)
if plan.returncode != 0:
    f("terraform plan not empty after adoption (rc=%s): %s" % (
        plan.returncode, (plan.stdout or plan.stderr).strip()[:300]))

# (6) state contents: local_file resources exactly { adopted files, manifest }
state_path = os.path.join(work, "terraform.tfstate")
expect = set()
for n in live_files:
    expect.add(os.path.abspath(os.path.join(work, "live", n)))
expect.add(os.path.abspath(os.path.join(work, "deployment.manifest")))
if not os.path.isfile(state_path):
    f("terraform.tfstate missing")
else:
    try:
        with open(state_path) as fh:
            st = json.load(fh)
        got = set()
        for res in st.get("resources", []):
            if res.get("type") != "local_file" or res.get("mode") != "managed":
                continue
            for inst in res.get("instances", []):
                attrs = inst.get("attributes", {}) or {}
                fn = attrs.get("filename")
                if fn:
                    got.add(os.path.abspath(os.path.join(work, fn)))
        if got != expect:
            f("state local_file filenames differ: expected=%r got=%r" % (
                sorted(expect), sorted(got)))
    except Exception as exc:  # noqa
        f("could not parse terraform.tfstate: %s" % exc)

print("CASE %s: %s" % (os.path.basename(work),
      "OK" if not fails else "; ".join(fails)))
sys.exit(1 if fails else 0)
PY
}

i=0
for src in /app/stack/live "$H/H1/live" "$H/H2/live" "$H/H3/live"; do
  i=$((i+1))
  if [ ! -d "$src" ]; then
    failadd "fixture missing: $src"
    continue
  fi
  work=/tmp/es_work_$i
  rm -rf "$work"
  mkdir -p "$work"
  cp -r "$src" "$work/live"

  if ! bash "$DELIV" "$work" >/tmp/es_deploy_$i.log 2>&1; then
    failadd "deploy.sh failed on case $i (see /tmp/es_deploy_$i.log)"
    continue
  fi

  if ! check_case "$work" "$src"; then
    FAIL=true
  fi
done

# ---------------------------------------------------------------------------
# Finish: write reward
# ---------------------------------------------------------------------------
if [ "$FAIL" = true ]; then
  echo "0" > /logs/verifier/reward.txt
else
  echo "1" > /logs/verifier/reward.txt
fi
echo "REWARD=$(cat /logs/verifier/reward.txt)"
exit 0
