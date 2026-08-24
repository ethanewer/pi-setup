#!/usr/bin/env bash
set -euo pipefail

cd /app/webapp
git checkout -q feature-eu
./deploy.sh

# Confirm the deployment.
test -f /srv/app/config.json
test -f /srv/app/DEPLOYMENT
grep -q '"env" *: *"eu"' /srv/app/config.json
grep -q '^branch=feature-eu$' /srv/app/DEPLOYMENT
cat /srv/app/DEPLOYMENT
