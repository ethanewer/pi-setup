#!/bin/bash
# Oracle for lunar-dial: author the sonar debugger, then RUN it on the visible
# station context to produce /app/depth.txt and /app/probes.json.
# Never reads /tests.
set -eu

SOLVER="/app/sonar.py"

# ---- 1. Write the deliverable program (this IS the work).
cat > "$SOLVER" <<'PY'
import json
import subprocess
import sys

GAUGE = "/app/bin/gauge"
BUDGET = 28


def probe(ctx, endpoint, k, log):
    r = subprocess.run([GAUGE, ctx, endpoint, str(k)],
                       capture_output=True, text=True, timeout=30)
    reply = r.stdout.strip()
    log.append({"endpoint": endpoint, "k": k, "reply": reply})
    return reply


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: python3 sonar.py <ctx> [depth_out] [probes_out]",
              file=sys.stderr)
        return 2
    ctx = args[0]
    depth_out = args[1] if len(args) > 1 else "/app/depth.txt"
    probes_out = args[2] if len(args) > 2 else "/app/probes.json"

    log = []
    # exponential bracketing: positions 0..L-1 are submerged (wet), L.. is not
    if probe(ctx, "wet", 0, log) != "1":
        hi = 0
    else:
        k = 1
        while True:
            if probe(ctx, "wet", k, log) == "0":
                break
            k *= 2
        lo, hi = k // 2, k  # last wet, first dry
        while lo + 1 < hi:
            mid = (lo + hi) // 2
            if probe(ctx, "wet", mid, log) == "1":
                lo = mid
            else:
                hi = mid
        depth = lo + 1  # positions 0..lo submerged
    boundary = probe(ctx, "core", hi, log)  # confirm bedrock just past L
    answer = hi if hi == 0 or boundary == "BEDROCK" else -1
    if answer < 0:
        print("sonar: boundary check failed", file=sys.stderr)
        return 1

    with open(depth_out, "w", encoding="utf-8") as fh:
        fh.write("%d\n" % answer)
    with open(probes_out, "w", encoding="utf-8") as fh:
        json.dump({
            "answer": answer,
            "calls": len(log),
            "budget": BUDGET,
            "problem": "tide-gauge-depth",
            "probes": log,
        }, fh, indent=2)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PY

chmod +x "$SOLVER"

# 2. Produce the visible artifacts from the shipped station context.
python3 "$SOLVER" /app/fixtures/station.json

echo "solve.sh done -> $SOLVER /app/depth.txt /app/probes.json"
cat /app/depth.txt
python3 -c "import json;d=json.load(open('/app/probes.json'));print('calls',d['calls'],'answer',d['answer'])"
