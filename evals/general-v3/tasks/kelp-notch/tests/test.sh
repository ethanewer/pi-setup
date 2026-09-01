#!/bin/bash
#
# kelp-notch verifier.
# Executes the deliverable /app/provision_lists.sh on the visible spec and on
# every hidden case in /tests/hidden (different domains, addresses,
# recipients; re-provisioning must remove stale entries), then validates the
# canonical /etc/postfix/virtual, main.cf registration, the postmap-built
# database, and both manifests. Writes the reward to
# /logs/verifier/reward.txt on every exit path.
set -u

mkdir -p /logs/verifier
RWD=/logs/verifier/reward.txt

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

fails=0
fail() { echo "FAIL: $1" >&2; fails=$((fails+1)); }

# crash-proof reward: 0 up front, overwritten only on a fully clean pass
printf 0 > "$RWD"
trap 'printf 0 > "$RWD"' INT TERM

SCRIPT=/app/provision_lists.sh
CANON=/etc/postfix/virtual

[ -f "$SCRIPT" ] || fail "missing /app/provision_lists.sh"
[ -x "$SCRIPT" ] || fail "provision_lists.sh not executable"
[ -f /app/list_manifest.json ] || fail "missing /app/list_manifest.json"

qmap() { # qmap <address> -> mapped value (empty if none)
  postmap -q "$1" "hash:$CANON" 2>/dev/null
}

if [ -f "$SCRIPT" ]; then
  # --- visible case: EXECUTE the deliverable on the supplied spec ---
  rm -f /tmp/kn_vis_manifest.json
  $TIMEOUT_CMD 120 bash "$SCRIPT" /app/lists.spec /tmp/kn_vis_manifest.json >/dev/null 2>&1 \
    || fail "visible:provision-failed"

  # canonical file + compiled database must exist
  [ -f "$CANON" ]     || fail "canonical:$CANON missing"
  [ -f "$CANON.db" ]  || fail "virtual.db not built (postmap)"

  # main.cf must register the canonical map and the list domain
  vmaps="$(postconf -h virtual_alias_maps 2>/dev/null || true)"
  case "$vmaps" in
    *"/etc/postfix/virtual"*) : ;;
    *) fail "virtual_alias_maps not declared for /etc/postfix/virtual" ;;
  esac
  vdoms="$(postconf -h virtual_alias_domains 2>/dev/null || true)"
  case "$vdoms" in
    *lists.thornway.internal*) : ;;
    *) fail "virtual_alias_domains missing list domain" ;;
  esac

  # every visible address must resolve through the built map
  for pair in "announce@lists.thornway.internal:steward" \
              "builders@lists.thornway.internal:steward" \
              "toolswap@lists.thornway.internal:warden"; do
    addr="${pair%%:*}"; rcpt="${pair#*:}"
    got="$(qmap "$addr")"
    [ "$got" = "$rcpt" ] || fail "lookup $addr -> '$got' (want '$rcpt')"
  done
  # an address that is not in the spec must not resolve
  got="$(qmap ghost@lists.thornway.internal)"
  [ -z "$got" ] || fail "stale mapping ghost@lists.thornway.internal resolved"

  # manifests (visible run + deliverable) must match the visible spec exactly
  check_vis_manifest() {
    python3 - "$1" <<'PY'
import json, sys

try:
    m = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    sys.exit(1)
if not isinstance(m, dict) or set(m) != {"domain", "canonical_config", "lists"}:
    sys.exit(1)
if m["domain"] != "lists.thornway.internal":
    sys.exit(1)
if m["canonical_config"] != "/etc/postfix/virtual":
    sys.exit(1)
want = [
    ("announce@lists.thornway.internal", "steward"),
    ("builders@lists.thornway.internal", "steward"),
    ("toolswap@lists.thornway.internal", "warden"),
]
try:
    got = [(e.get("address"), e.get("recipient")) for e in m["lists"]]
except Exception:
    sys.exit(1)
sys.exit(0 if got == want else 1)
PY
  }
  check_vis_manifest /tmp/kn_vis_manifest.json || fail "visible manifest mismatch"
  check_vis_manifest /app/list_manifest.json   || fail "list_manifest.json mismatch"

  # --- hidden cases: distinct domains/addresses/recipients ---
  checked=0
  for dir in /tests/hidden/*/; do
    spec="${dir}spec.tsv"; exp="${dir}expected.json"
    [ -f "$spec" ] || continue
    [ -f "$exp" ]  || continue
    checked=$((checked+1))
    rm -f /tmp/kn_case_manifest.json
    if ! $TIMEOUT_CMD 120 bash "$SCRIPT" "$spec" /tmp/kn_case_manifest.json >/dev/null 2>&1; then
      fail "hidden $(basename "$dir"): provision-failed"
      continue
    fi
    python3 - "$exp" <<'PY' || fail "hidden $(basename "$dir") failed"
import json, subprocess, sys

exp_path = sys.argv[1]
try:
    exp = json.load(open(exp_path, encoding="utf-8"))
    got = json.load(open("/tmp/kn_case_manifest.json", encoding="utf-8"))
except Exception:
    sys.exit(1)
if not isinstance(got, dict) or set(got) != {"domain", "canonical_config", "lists"}:
    sys.exit(1)
if got.get("canonical_config") != "/etc/postfix/virtual":
    sys.exit(1)
if got.get("domain") != exp.get("domain"):
    sys.exit(1)
try:
    glist = [(e.get("address"), e.get("recipient")) for e in got["lists"]]
except Exception:
    sys.exit(1)
want = [(e["address"], e["recipient"]) for e in exp.get("lists", [])]
if glist != want:
    sys.exit(1)

def qmap(addr):
    r = subprocess.run(
        ["postmap", "-q", addr, "hash:/etc/postfix/virtual"],
        capture_output=True, text=True,
    )
    return r.stdout.strip()

for addr, rcpt in want:
    if qmap(addr) != rcpt:
        sys.exit(1)
for addr in exp.get("stale", []):
    if qmap(addr) != "":
        sys.exit(1)

# main.cf must be re-pointed at this case's domain and the canonical map
r = subprocess.run(["postconf", "-h", "virtual_alias_maps"],
                   capture_output=True, text=True)
if "/etc/postfix/virtual" not in r.stdout:
    sys.exit(1)
r = subprocess.run(["postconf", "-h", "virtual_alias_domains"],
                   capture_output=True, text=True)
if exp.get("domain") not in r.stdout:
    sys.exit(1)
sys.exit(0)
PY
  done
  [ "$checked" -ge 1 ] || fail "hidden:no-cases-verified"
fi

if [ "$fails" = "0" ]; then
  printf 1 > "$RWD"
else
  printf 0 > "$RWD"
  echo "kelp-notch verifier FAIL ($fails problems)" >&2
fi
echo "REWARD=$(cat "$RWD")"
exit 0
