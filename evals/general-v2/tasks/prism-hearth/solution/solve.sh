#!/bin/bash
#
# Oracle for prism-hearth.
# Authors the deliverable /app/infer.py (the working program), then RUNS it on
# the visible scenario so the primary deliverables (/app/loss.txt and
# /app/batch_plan.json) are produced. Never reads /tests.
set -euo pipefail

# Deliver the working reference program.
cp /solution/infer.py /app/infer.py
chmod +x /app/infer.py
echo "oracle: /app/infer.py delivered"

# Run the real work: execute the pipeline on the visible scenario, writing all
# outputs (incl. /app/loss.txt and /app/batch_plan.json) into /app.
python3 /app/infer.py /app/job.json /app

echo "oracle: deliverables:"
ls -la /app/loss.txt /app/batch_plan.json /app/heads.json /app/grad.json /app/lm_head.json /app/critical.json
echo "oracle run complete"