#!/usr/bin/env bash
# Submit the nightly batch job. Returns immediately; the job itself writes to batch.log.
set -euo pipefail
cd "$(dirname "$0")/.."
: > batch.log
nohup python3 batch/batch_job.py > batch/launcher.log 2>&1 &
echo $! > batch/batch.pid
echo "batch: job submitted (pid $(cat batch/batch.pid)); progress will appear in batch.log"
