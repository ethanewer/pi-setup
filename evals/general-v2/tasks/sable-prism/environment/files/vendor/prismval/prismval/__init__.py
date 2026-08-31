"""prismval: a tiny deterministic multiple-choice eval harness.

Contract (all of it is deterministic so a verifier can recompute every
number independently):

* A task config (JSON) declares:
    - "task_name": string.
    - "choices":   ordered list of DISTINCT class-name strings; this is the
      choice order of the benchmark task.  Gold indices index into THIS list.
    - "model_path": path to a lexicon model JSON.
    - "text_column": which JSONL field of each document holds the text.
    - "gold_map":   object mapping label-code strings ("0", "1", ...) to
      INTEGER indices into "choices".
    - "prompt_template": a str.format template with a "{text}" placeholder.

* The model JSON has the shape
      {"classes": ["<name>", ...],           # fixed internal class order
       "bias":   [b0, b1, ...],              # one float per class
       "weights": {"token": [w0, w1, ...]}}  # additive weight per class
  Score of class k = bias[k] + sum of weights[token][k] over the tokens of
  the document text (tokenize: lowercase, keep [a-z0-9']+ runs).
  Predicted class = argmax score, ties broken by the FIRST class in
  model["classes"] order.

* Gold files are JSON: {"codebook": {"<code>": "<class name>", ...},
  "labels": {"<doc id>": <code int>}}.  The codebook documents what each
  label code means; the HARNESS itself only trusts the config's gold_map.

* A document is SCORED only when its label exists, is a true int, and
  str(code) is a key of gold_map whose value is a valid index into
  choices.  Everything else is SKIPPED (never counted in n/accuracy) with
  reason "invalid-label" or "gold-out-of-range".
"""
