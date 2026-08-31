#!/bin/bash
#
# reed-haven verifier.
# Runs the deliverable /app/provision.sh (twice: idempotency), confirms the
# canonical /etc/listd/config.toml content, confirms /app/roster.json against
# the expected visible report, then EXECUTES the deliverable config through
# the listd daemon on every hidden administrative stream and compares against
# each stream's expected report. Finally proves the failure mode: with the
# canonical config temporarily removed the daemon must refuse to run.
# Writes REWARD (0/1) to /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
printf 0 > /logs/verifier/reward.txt

LISTD=/app/listd.py
CONFIG=/etc/listd/config.toml

TMP=$(mktemp -d)
overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
  echo "reed-haven verifier: overall=$overall${msgs:+:${msgs}}" >&2
}
trap 'finalize_reward; rm -rf "$TMP"' EXIT

note() { msgs="$msgs $1"; }

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

# --- every deliverable must be present --------------------------------------
for f in /app/provision.sh /app/roster.json; do
  [ -e "$f" ] || { overall=0; note "deliverable-missing:$f"; }
done

# --- run the provisioning deliverable (twice; idempotent) --------------------
if [ -x /app/provision.sh ] || [ -f /app/provision.sh ]; then
  $TIMEOUT_CMD 120 bash /app/provision.sh >>"$TMP/prov.log" 2>&1 \
    || { overall=0; note "provision.sh:run1-crashed"; }
  sha1=$(sha256sum /app/roster.json 2>/dev/null | awk '{print $1}' || true)
  $TIMEOUT_CMD 120 bash /app/provision.sh >>"$TMP/prov.log" 2>&1 \
    || { overall=0; note "provision.sh:run2-crashed"; }
  sha2=$(sha256sum /app/roster.json 2>/dev/null | awk '{print $1}' || true)
  if [ -n "$sha1" ] && [ -n "$sha2" ] && [ "$sha1" != "$sha2" ]; then
    overall=0; note "provision.sh:not-idempotent"
  fi
else
  overall=0; note "provision.sh:missing-or-not-runnable"
fi

# --- canonical config exists with required content ---------------------------
if [ ! -f "$CONFIG" ]; then
  overall=0; note "canonical-config-missing"
else
  grep -q 'heron-announce' "$CONFIG" || { overall=0; note "config:no-heron-announce"; }
  grep -q 'tide-chat' "$CONFIG"        || { overall=0; note "config:no-tide-chat"; }
  grep -q 'reedhaven.example' "$CONFIG" || { overall=0; note "config:no-site-domain"; }
  grep -q 'ada.l@example.net' "$CONFIG" || { overall=0; note "config:no-ada"; }
  grep -q 'keeper@reedhaven.example' "$CONFIG" || { overall=0; note "config:no-keeper"; }
fi

# --- daemon sanity: it exists and is python3-runnable ------------------------
[ -f "$LISTD" ] || { overall=0; note "listd:missing"; }

# --- visible roster ----------------------------------------------------------
if [ "$overall" = "1" ]; then
  python3 - /app/roster.json /tests/expected.json <<'PY'
import json, sys

def load(p):
    with open(p, encoding='utf-8') as fh:
        return json.load(fh)

got = load(sys.argv[1])
want = load(sys.argv[2])
if got != want:
    print("visible roster mismatch", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
  [ $? -eq 0 ] || { overall=0; note "visible:roster-mismatch"; }
fi

# --- hidden streams: EXECUTE the deliverable config through the daemon -------
scen=0
for dir in /tests/hidden/*/; do
  name=$(basename "$dir")
  [ -f "$dir/stream.txt" ] || continue
  [ -f "$dir/expected.json" ] || { overall=0; note "$name:missing-expected"; continue; }
  scen=$((scen+1))
  [ "$overall" = "1" ] || continue
  out="$TMP/out_$name.json"
  rm -f "$out"
  $TIMEOUT_CMD 60 python3 "$LISTD" --config "$CONFIG" --stream "$dir/stream.txt" --out "$out" \
    >>"$TMP/listd.log" 2>&1
  if [ $? -ne 0 ] || [ ! -f "$out" ]; then
    overall=0; note "$name:daemon-run-failed"
  else
    python3 - "$out" "$dir/expected.json" <<'PY'
import json, sys

def load(p):
    with open(p, encoding='utf-8') as fh:
        return json.load(fh)

got = load(sys.argv[1])
want = load(sys.argv[2])
if got != want:
    print("hidden stream mismatch", file=sys.stderr)
    sys.exit(1)
sys.exit(0)
PY
    [ $? -eq 0 ] || { overall=0; note "$name:stream-mismatch"; }
  fi
done
[ "$scen" -ge 1 ] || { overall=0; note "hidden:no-scenarios"; }

# --- failure-mode proof: config away from its canonical path is not honored --
if [ "$overall" = "1" ] && [ -f "$CONFIG" ]; then
  mv "$CONFIG" "$TMP/config.hold"
  out="$TMP/wrongpath.json"
  rm -f "$out"
  $TIMEOUT_CMD 60 python3 "$LISTD" --config "$CONFIG" --stream /app/fixtures/stream.txt --out "$out" \
    >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ] || [ -e "$out" ]; then
    overall=0; note "wrongpath:daemon-did-not-refuse"
  fi
  mv "$TMP/config.hold" "$CONFIG"
fi

exit 0
