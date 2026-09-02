#!/bin/bash
#
# brisk-kiln verifier.
# Executes the deliverables: parses /app/lists.conf against the documented
# schema, confirms the canonical placement /etc/listd/lists.conf, executes
# /app/install.sh, restarts the daemon (which only ever reads the canonical
# path), and probes the live HTTP API. Hidden probe suites in /tests/hidden
# exercise membership/posting/subscribe/archive/restart behavior. Writes
# REWARD (0/1) to /logs/verifier/reward.txt on EVERY exit path (EXIT trap).
set -u

mkdir -p /logs/verifier

TIMEOUT_CMD=$(command -v timeout || true)
[ -n "${TIMEOUT_CMD-}" ] || TIMEOUT_CMD=""

CTL=/opt/listd/ctl.sh
overall=1
msgs=""

finalize_reward() {
  if [ "${overall:-0}" = "1" ]; then
    printf 1 > /logs/verifier/reward.txt
  else
    printf 0 > /logs/verifier/reward.txt
  fi
}
trap 'finalize_reward' EXIT
printf 0 > /logs/verifier/reward.txt

log() { echo "brisk-kiln verify: $*" >&2; }

# ---------------------------------------------------------------------------
# 1. Static check of /app/lists.conf against the required configuration.
# ---------------------------------------------------------------------------
if [ ! -f /app/lists.conf ]; then
  overall=0; msgs="$msgs missing:lists.conf"
elif [ ! -f /app/install.sh ]; then
  overall=0; msgs="$msgs missing:install.sh"
else
  python3 - <<'PY' || { overall=0; msgs="$msgs lists.conf:spec-mismatch"; }
import configparser
import sys

try:
    cp = configparser.ConfigParser()
    cp.read("/app/lists.conf")
except Exception as exc:
    print("static check: parse error: %s" % exc, file=sys.stderr)
    sys.exit(1)

try:
    assert set(cp.sections()) == {"global", "list.announce",
                                  "list.chatter", "list.alerts"}, cp.sections()
    g = cp["global"]
    assert g["hostname"].strip() == "lists.grebe-lake.net", g["hostname"]
    assert g["spool"].strip() == "/var/spool/listd", g["spool"]
    assert str(g["port"]).strip() == "8418", g["port"]
    expect = {
        "announce": ("ops@grebe-lake.net", True,
                     {"ops@grebe-lake.net", "warden@grebe-lake.net"}),
        "chatter": ("rosa@grebe-lake.net", False,
                    {"rosa@grebe-lake.net", "finn@example.org"}),
        "alerts": ("ops@grebe-lake.net", True,
                   {"ops@grebe-lake.net"}),
    }
    for name, (owner, closed, members) in expect.items():
        sec = cp["list." + name]
        assert sec["owner"].strip() == owner, (name, sec["owner"])
        val = str(sec["closed"]).strip().lower()
        if closed:
            assert val in ("true", "yes", "on", "1"), (name, "closed")
        else:
            assert val in ("false", "no", "off", "0"), (name, "closed")
        got_members = [m.strip() for m in str(sec["members"]).split(",") if m.strip()]
        assert set(got_members) == set(members), (name, got_members)
except Exception as exc:
    print("static check failed: %s" % exc, file=sys.stderr)
    sys.exit(1)
PY
fi

# ---------------------------------------------------------------------------
# Canonical placement: /etc/listd/lists.conf must exist and equal the
# deliverable BEFORE the verifier runs the installer.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if [ ! -f /etc/listd/lists.conf ]; then
    overall=0; msgs="$msgs canonical:missing"
  elif ! cmp -s /app/lists.conf /etc/listd/lists.conf; then
    overall=0; msgs="$msgs canonical:differs-from-deliverable"
  fi
fi

# ---------------------------------------------------------------------------
# Execute the installer deliverable (idempotent), then reload from the
# canonical path and confirm health.
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  if ! $TIMEOUT_CMD 90 bash /app/install.sh >/tmp/bk_install.log 2>&1; then
    overall=0; msgs="$msgs install:failed"
  fi
  if ! $TIMEOUT_CMD 60 /opt/listd/ctl.sh restart >>/tmp/bk_install.log 2>&1; then
    overall=0; msgs="$msgs ctl:restart-failed"
  fi
  if [ "$overall" = "1" ]; then
    if ! python3 - <<'PY'
import json, sys, urllib.request
try:
    with urllib.request.urlopen("http://127.0.0.1:8418/health", timeout=5) as r:
        body = json.load(r)
    assert body.get("status") == "ok", body
    assert body.get("config") == "/etc/listd/lists.conf", body
except Exception as exc:
    print("health check failed: %s" % exc, file=sys.stderr)
    sys.exit(1)
PY
    then
      overall=0; msgs="$msgs health:failed"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Hidden behavioral probes (run in order; each is self-contained).
# ---------------------------------------------------------------------------
if [ "$overall" = "1" ]; then
  probes=0
  for p in /tests/hidden/probe_*/probe.py; do
    [ -f "$p" ] || continue
    probes=$((probes+1))
    if ! $TIMEOUT_CMD 60 python3 "$p" >/tmp/bk_probe.log 2>&1; then
      overall=0
      msgs="$msgs probe-failed:$(basename "$(dirname "$p")")"
      tail -5 /tmp/bk_probe.log >&2 2>/dev/null || true
    fi
  done
  [ "$probes" -ge 1 ] || { overall=0; msgs="$msgs no-hidden-probes"; }
fi

if [ "$overall" = "1" ]; then
  log "all checks passed"
else
  log "FAIL${msgs:+:${msgs}}"
fi
finalize_reward
exit 0
