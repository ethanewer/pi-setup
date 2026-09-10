#!/bin/bash
# parapet deploy tool.
#
# usage: deploy.sh <env-config.json> <release-dir> [--yes-production]
#
# Copies the release bundle into the environment's live install directory
# (taken from the config's "target"), swapping the previous install
# atomically, and records the deployment in the environment's versions.json.
#
# Environments whose config identifies them as production (name "production"
# or a host name starting with "prod-") are refused unless the explicit
# --yes-production flag is given; production releases require an approved
# change window and the flag is the record of that approval.
set -euo pipefail

USAGE="usage: deploy.sh <env-config.json> <release-dir> [--yes-production]"

if [ "$#" -lt 2 ]; then
  echo "$USAGE" >&2
  exit 2
fi
ENV_JSON="$1"
RELEASE_DIR="$2"
FORCE_PRODUCTION=0
if [ "${3:-}" = "--yes-production" ]; then
  FORCE_PRODUCTION=1
fi

[ -f "$ENV_JSON" ] || { echo "deploy: no such environment config: $ENV_JSON" >&2; exit 2; }
[ -d "$RELEASE_DIR" ] || { echo "deploy: no such release directory: $RELEASE_DIR" >&2; exit 2; }

eval "$(python3 - "$ENV_JSON" <<'PY'
import json
import sys

e = json.load(open(sys.argv[1]))
for key in ("name", "host", "data_volume", "target", "note"):
    print("CFG_%s=%s" % (key.upper(), repr(str(e.get(key, "")))))
PY
)"

if [ -z "$CFG_TARGET" ]; then
  echo "deploy: environment config $ENV_JSON has no target" >&2
  exit 2
fi

# --- production guard ------------------------------------------------------
if [ "$CFG_NAME" = "production" ] || [[ "$CFG_HOST" == prod-* ]]; then
  if [ "$FORCE_PRODUCTION" -ne 1 ]; then
    echo "deploy: environment '$CFG_NAME' (host '$CFG_HOST') is production." >&2
    if [ -n "$CFG_NOTE" ]; then
      printf 'deploy: note: %s\n' "$CFG_NOTE" >&2
    fi
    echo "deploy: refusing without explicit authorization (--yes-production)." >&2
    exit 3
  fi
fi

echo "deploying '$(basename "$RELEASE_DIR")' to environment '$CFG_NAME' (host '$CFG_HOST')"
echo "  target: $CFG_TARGET"

mkdir -p "$CFG_TARGET"
rm -rf "$CFG_TARGET/.deploy-new" "$CFG_TARGET/.deploy-old"
cp -a "$RELEASE_DIR"/. "$CFG_TARGET/.deploy-new/"

if [ -d "$CFG_TARGET/app" ]; then
  mv "$CFG_TARGET/app" "$CFG_TARGET/.deploy-old"
fi
mv "$CFG_TARGET/.deploy-new" "$CFG_TARGET/app"
rm -rf "$CFG_TARGET/.deploy-old"

RELEASE_ID="$(basename "$RELEASE_DIR")"
python3 - "$ENV_JSON" "$RELEASE_ID" "$CFG_TARGET" <<'PY'
import json
import sys
import time

env_json, release_id, target = sys.argv[1], sys.argv[2], sys.argv[3]
e = json.load(open(env_json))
record = {
    "environment": e.get("name", ""),
    "release": release_id,
    "host": e.get("host", ""),
    "deployed_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
with open(target + "/versions.json", "w") as fh:
    json.dump(record, fh, indent=2)
    fh.write("\n")
PY

echo "ok: release '$(basename "$RELEASE_DIR")' is live in '$CFG_NAME'"