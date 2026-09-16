#!/usr/bin/env bash
# Builds the /app/enrichd checkout at image build time: runs the repository
# generator, creates the visible workload fixture, and commits a short git
# history so the checkout arrives as a real repository.
set -euo pipefail
cd /app

python3 tools/gen_repo.py --out /app/enrichd
mkdir -p /app/enrichd/workloads
python3 tools/gen_workload.py --seed 5 --clients 160 --rounds 7 \
    --start-ts 1772140000 --out /app/enrichd/workloads/visible.jsonl

cd /app/enrichd
git init -q
git add README.md pyproject.toml Makefile .gitignore \
    enrichd/__init__.py enrichd/__main__.py enrichd/cli.py enrichd/engine.py \
    enrichd/output.py enrichd/stats.py
git commit -q -m "enrichd: initial streaming enrichment service"
git add enrichd/protocol.py enrichd/embed.py enrichd/fingerprint.py enrichd/cache.py
git commit -q -m "enrichd: profile cache and deterministic feature material"
git add tests workloads
git commit -q -m "enrichd: unit suite and visible load fixture"

echo "build_repo.sh: checkout at /app/enrichd ($(git -C /app/enrichd rev-list --count HEAD) commits)"