#!/usr/bin/env python3
"""Extract the integer part (truncation toward -inf: floor) of the reported
objective from /app/metrics.json and persist exactly one integer to
/app/answer.txt, then exit 0."""
import json
import math

with open("/app/metrics.json", "r", encoding="utf-8") as fh:
    metrics = json.load(fh)

raw = metrics["report"]["reported_objective"]
answer = math.floor(raw)

with open("/app/answer.txt", "w", encoding="utf-8") as fh:
    fh.write(str(answer) + "\n")

print(answer)