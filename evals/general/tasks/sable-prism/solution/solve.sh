#!/bin/bash
# Oracle for sable-prism: install the vendored harness, author the task config
# wiring (honouring the scrambled codebook), write the eval driver, and run it
# on the visible fixture to produce the baseline result. Never reads /tests.
set -eu

CFG="/app/task_cfg.json"
DRIVER="/app/run_eval.sh"
BASELINE="/app/results/tone_triage/baseline.json"

# 1. Install the vendored harness package (offline).
pip install --no-build-isolation -e /app/vendor/prismval >/tmp/prismval_install.log 2>&1

# 2. Author the task config. Codebook (scrambled): 0=positive, 1=negative,
#    2=neutral. choices order is [negative, neutral, positive], so:
#    code "0" -> positive -> index 2, code "1" -> negative -> index 0,
#    code "2" -> neutral -> index 1.
cat > "$CFG" <<'JSON'
{
  "task_name": "tone_triage",
  "choices": ["negative", "neutral", "positive"],
  "model_path": "/app/model/lexicon.json",
  "text_column": "text",
  "gold_map": {"0": 2, "1": 0, "2": 1},
  "prompt_template": "Review: {text}\nQuestion: what is the overall tone of this review?\nAnswer:"
}
JSON

# 3. Write the eval driver.
cat > "$DRIVER" <<'SH'
#!/bin/bash
set -eu
if [ "$#" -eq 0 ]; then
  mkdir -p /app/results/tone_triage
  exec python3 -m prismval \
    --config /app/task_cfg.json \
    --data /app/data/reviews.jsonl \
    --gold /app/data/gold.json \
    --out /app/results/tone_triage/baseline.json
fi
if [ "$1" = "eval" ]; then
  exec python3 -m prismval --config "$2" --data "$3" --gold "$4" --out "$5"
fi
echo "usage: run_eval.sh [eval <config> <data> <gold> <out>]" >&2
exit 2
SH
chmod +x "$DRIVER"

# 4. Run the visible suite to produce the baseline deliverable.
mkdir -p /app/results/tone_triage
bash "$DRIVER"

echo "oracle done"
ls -l "$CFG" "$DRIVER" "$BASELINE"
