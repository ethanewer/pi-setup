#!/bin/bash
# slate-quarry verifier. Executes the delivered /app/ops.sh as the
# unprivileged user dana (so privileged effects must come from the configured
# sudo rule), asserts the exact end-state, then re-runs the deliverable on
# hidden degraded states (wiped gate, stale/wrong-ownership gate, repeat runs).
set -u
mkdir -p /logs/verifier
REWARD=0
LOG(){ echo "$*"; }

PRISTINE_SNAPCTL_SHA="40f8a3c95af5c481aec1bc7dc7ae11c064fa15b8650338279537dd57d669db3f"
PRISTINE_SUDOERS_SHA="c999f1fc20e1273293a67e1cd2007b74158a639a5a684e814f5363cc18b9a126"

SEAL_NAME=nightly-rotator
SEAL=/var/lib/snapshotd/gate/nightly-rotator.seal
LEDGER=/opt/quarry-vault/rotating/ledger.bin

expected_seal_body() {
  printf 'snapshotd-seal:v1:%s:%s' "$SEAL_NAME" \
    "$(printf 'snapshotd-seal:v1:%s' "$SEAL_NAME" | sha256sum | awk '{print $1}')"
}

check_tamper() {
  [ -f /usr/local/bin/snapshotctl ] || { LOG "snapshotctl missing"; return 1; }
  local s; s="$(sha256sum /usr/local/bin/snapshotctl | awk '{print $1}')"
  [ "$s" = "$PRISTINE_SNAPCTL_SHA" ] || { LOG "snapshotctl was modified"; return 1; }
  [ -f /etc/sudoers.d/quarry ] || { LOG "sudoers rule missing"; return 1; }
  s="$(sha256sum /etc/sudoers.d/quarry | awk '{print $1}')"
  [ "$s" = "$PRISTINE_SUDOERS_SHA" ] || { LOG "sudoers rule was modified"; return 1; }
  return 0
}

check_state() {
  # tamper guards
  check_tamper || return 1
  # base runtime dir untouched
  [ "$(stat -c %U /var/lib/snapshotd)" = "root" ] || { LOG "/var/lib/snapshotd owner wrong"; return 1; }
  [ "$(stat -c %a /var/lib/snapshotd)" = "755" ] || { LOG "/var/lib/snapshotd mode wrong"; return 1; }
  # gate dir: root-only, root-owned
  [ -d /var/lib/snapshotd/gate ] || { LOG "gate dir missing"; return 1; }
  [ "$(stat -c %U /var/lib/snapshotd/gate)" = "root" ] || { LOG "gate dir owner wrong"; return 1; }
  [ "$(stat -c %a /var/lib/snapshotd/gate)" = "700" ] || { LOG "gate dir mode wrong"; return 1; }
  # seal present, root-owned, exactly current
  [ -f "$SEAL" ] || { LOG "seal file missing"; return 1; }
  [ "$(stat -c %U "$SEAL")" = "root" ] || { LOG "seal not root-owned"; return 1; }
  local want; want="$(expected_seal_body)"
  grep -qx "$want" "$SEAL" || { LOG "seal content stale/wrong"; return 1; }
  # the tool itself must accept the seal (verify subcommand)
  /usr/local/bin/snapshotctl verify "$SEAL_NAME" >/dev/null 2>&1 || { LOG "snapshotctl verify failed"; return 1; }
  # ledger destroyed, vault perms untouched
  [ ! -e "$LEDGER" ] || { LOG "ledger still present"; return 1; }
  [ "$(stat -c %U /opt/quarry-vault/rotating)" = "root" ] || { LOG "vault owner wrong"; return 1; }
  [ "$(stat -c %a /opt/quarry-vault/rotating)" = "711" ] || { LOG "vault mode wrong"; return 1; }
  # report deliverable
  [ -s /app/ops-report.txt ] || { LOG "ops-report.txt missing/empty"; return 1; }
  grep -q '^slate-quarry ops report - ' /app/ops-report.txt || { LOG "report header missing"; return 1; }
  grep -q 'SEAL' /app/ops-report.txt || { LOG "report SEAL label missing"; return 1; }
  grep -q 'snapshotctl seal nightly-rotator' /app/ops-report.txt || { LOG "report seal command missing"; return 1; }
  grep -q 'DESTROY' /app/ops-report.txt || { LOG "report DESTROY label missing"; return 1; }
  grep -q 'shred -u /opt/quarry-vault/rotating/ledger.bin' /app/ops-report.txt || { LOG "report shred command missing"; return 1; }
  return 0
}

run_ops() {
  chmod 0755 /app/ops.sh 2>/dev/null || true
  su -s /bin/bash dana -c 'bash /app/ops.sh' >/tmp/ops.out 2>/tmp/ops.err
}

# ---- deliverable present?
if [ ! -f /app/ops.sh ]; then
  LOG "DELIVERABLE /app/ops.sh missing"
  echo "$REWARD" > /logs/verifier/reward.txt
  exit 0
fi

# ---- visible run: execute the deliverable as dana, assert end-state
if run_ops && check_state; then
  LOG "visible run: PASS"
  REWARD=1
else
  LOG "visible run: FAIL"
  tail -5 /tmp/ops.err 2>/dev/null || true
  echo "$REWARD" > /logs/verifier/reward.txt
  exit 0
fi

# ---- hidden degraded-state cases
for c in /tests/hidden/*.sh; do
  [ -f "$c" ] || continue
  if bash "$c" && run_ops && check_state; then
    LOG "hidden $(basename "$c"): PASS"
  else
    LOG "hidden $(basename "$c"): FAIL"
    REWARD=0
    break
  fi
done

echo "$REWARD" > /logs/verifier/reward.txt
exit 0
