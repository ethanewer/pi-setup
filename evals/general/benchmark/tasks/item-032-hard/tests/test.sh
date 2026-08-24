#!/bin/bash
# Verifier for item-032-hard.
if [ ! -f /app/final.txt ] || [ ! -f /app/log.json ]; then
  echo "0" > /logs/verifier/reward.txt
  exit 0
fi

score=$(python3 - <<'EOF'
import json
txt = open("/app/final.txt", "r", errors="replace").read()
low = txt.lower()

esc_clean = ("\x1b" not in txt) and ("\x08" not in txt)
no_anim = ("saving" not in low)

phrases = [
    "vault menu",
    "stored: gold",
    "stored: silver",
    "total: 2",
    "removed: silver",
    "total: 1",
    "logged out",
]
hits = sum(1 for p in phrases if p in low)

log_ok = False
try:
    log = json.load(open("/app/log.json"))
    log_ok = log.get("commands") == ["store gold","store silver","total","report","remove silver","total","report","quit"]
except Exception:
    pass

score = 0.0
if esc_clean and no_anim:
    if hits == len(phrases):
        score = 1.0
    elif hits >= 5:
        score = 0.6
    elif hits >= 4:
        score = 0.4
    elif hits >= 3:
        score = 0.2
    if score == 1.0 and not log_ok:
        score = 0.8
elif esc_clean:
    # Even without perfect animation handling, credit strong partial progress.
    if hits >= len(phrases):
        score = 0.5
    elif hits >= 4:
        score = 0.3
elif hits >= 5:
    score = 0.2

print(f"{score:.2f}", end="")
EOF
)
printf "%s" "$score" > /logs/verifier/reward.txt
echo "reward=$score"