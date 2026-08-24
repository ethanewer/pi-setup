#!/bin/bash
set -euo pipefail
cd /app/repo
git bundle create /app/repo.bundle --all
rm -rf /tmp/restore
git clone /app/repo.bundle /tmp/restore