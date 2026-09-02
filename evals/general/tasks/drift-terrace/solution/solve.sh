#!/bin/bash
# drift-terrace oracle: builds the deliverables by doing the real work.
# Writes the config, then runs the trainer which produces the model, the
# plain numeric vector file, and config/progress under the experiment dir.
# Never reads /tests.
set -euo pipefail

cd /app

cat > /app/config.yaml <<'YAML'
data:
  path: /app/company.csv
  target_column: churn
  drop_columns: []
  id_column: null
model:
  reg_strength: 0.05
  max_iter: 400
optim:
  driver_feature: driver_price
  bound_epsilon: 0.0001
split:
  seed: 812
  n_folds: 5
  held_out_fold: 4
evaluate:
  accuracy_floor: 0.820
debug:
  one_epoch: false
output:
  dir: /app
  model_file: model.joblib
  vector_file: vector.out
  log_dir: /app/experiment-data
  progress_file: progress.log
YAML

# train.py is shipped alongside this script in the source tree; plant it at
# /app/train.py (a required deliverable) and run it to produce the artifacts.
cp "$(dirname "$0")/train.py" /app/train.py
chmod +x /app/train.py

python3 /app/train.py --config /app/config.yaml

# The trainer writes into output.dir=/app, so these deliverables should now
# exist at their literal /app paths; require them before declaring success.
[ -f /app/model.joblib ] || { echo 'solve.sh: /app/model.joblib not produced' >&2; exit 1; }
[ -f /app/vector.out ] || { echo 'solve.sh: /app/vector.out not produced' >&2; exit 1; }
exit $?