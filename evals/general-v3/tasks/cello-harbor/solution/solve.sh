#!/bin/bash
# Real oracle for cello-harbor: write the scheduler program, then RUN it on the
# visible fixture to produce /app/plan.json. Never reads /tests.
set -eu

SOLVER="/app/solve.py"
OUT="/app/plan.json"

cat > "$SOLVER" <<'PY'
import json
import sys


def schedule(stream):
    budget = stream["budget"]
    sector = budget["sector"]
    max_seg = budget["max_segment_ms"]
    win_cap = budget["window_ms"]

    windows = []      # list of {"window_id","ms","segments"}
    cur_win = None    # (index, dict)
    cur_seg = None    # dict

    for chunk in stream["chunks"]:
        cid, ms = chunk["id"], chunk["ms"]
        placed = False
        # 1) try to append to the current segment
        if cur_seg is not None:
            seg_new = cur_seg["ms"] + ms
            win_new = cur_win["ms"] + ms
            if seg_new <= max_seg and win_new <= win_cap:
                cur_seg["chunks"].append(cid)
                cur_seg["ms"] = seg_new
                cur_win["ms"] = win_new
                placed = True
        # 2) open a new segment in the current window
        if not placed and cur_win is not None and ms <= max_seg \
                and cur_win["ms"] + ms <= win_cap:
            cur_seg = {"segment_id": "w%d-s%d" % (cur_win["index"],
                                                  len(cur_win["segments"])),
                       "chunks": [cid], "ms": ms}
            cur_win["segments"].append(cur_seg)
            cur_win["ms"] += ms
            placed = True
        # 3) open a new window (deadline check: earliest index is safest)
        if not placed:
            if cur_win is not None and cur_seg is not None:
                cur_win = None
                cur_seg = None
            idx = len(windows)
            if chunk["due"] < idx:
                raise ValueError(
                    "infeasible: chunk %s due %d but already at window %d"
                    % (cid, chunk["due"], idx))
            if idx >= budget["windows"]:
                raise ValueError("infeasible: window budget exhausted")
            cur_win = {"index": idx, "window_id": "w%d" % idx, "ms": ms,
                       "segments": []}
            cur_seg = {"segment_id": "w%d-s0" % idx, "chunks": [cid], "ms": ms}
            cur_win["segments"].append(cur_seg)
            windows.append(cur_win)

    for w in windows:
        del w["index"]
    return {"budget": budget, "windows": windows}


def main():
    stream_path, out_path = sys.argv[1], sys.argv[2]
    with open(stream_path, "r", encoding="utf-8") as fh:
        stream = json.load(fh)
    plan = schedule(stream)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(plan, fh, indent=2)


if __name__ == "__main__":
    main()
PY

chmod +x "$SOLVER"

python3 "$SOLVER" /app/stream.json "$OUT"

echo "solve.sh done -> $SOLVER and $OUT"
ls -l "$SOLVER" "$OUT"
