#!/usr/bin/env python3
"""zephyr-grove scheduling/arrangement engine.

Usage:  python3 solver.py CONFIG.JSON OUTDIR

Reads a scheduling config (JSON) and recomputes, deterministically, three
deliverables into OUTDIR:

  answer.txt  - number of distinct subsets of the "allowed" pool whose values
                sum exactly to target_sum (every element used at most once;
                only allowed numbers appear). A plain integer, no trailing
                newline, no surrounding text.
  grid.txt    - a solved 9x9 arrangement (a Latin square of order 9) rendered as
                9 rows, each with 9 space-separated two-digit zero-padded
                integer tokens over the allowed digits 1..9 (row-major).
  plans.txt   - JSON availability-overlap results: every maximal contiguous
                window inside the weekday business-hours span, outside the lunch
                window, where ALL people are simultaneously free for at least
                duration_needed minutes.

Everything is computed from the config on every run, so the program generalizes
to any new config with the same schema. No randomness; fully deterministic.
"""
import json
import os
import sys

DEFAULTS = {
    "business_start": 540,
    "business_end": 1020,
    "lunch_start": 720,
    "lunch_end": 780,
    "duration_needed": 30,
    "allowed": [],
    "target_sum": 0,
    "busy": {},
}


def hhmm(minute):
    minute = max(0, min(int(minute), 1439))
    return "%02d:%02d" % (minute // 60, minute % 60)


def subset_sum_count(allowed, target):
    """Count subsets (by element position, each used at most once) summing to target."""
    target = int(target)
    if target < 0:
        return 0
    # skip non-positive values; keep duplicates as distinct elements
    vals = [int(a) for a in allowed if isinstance(a, (int, float)) and int(a) > 0]
    dp = [0] * (target + 1)
    dp[0] = 1
    for a in vals:
        for s in range(target, a - 1, -1):
            dp[s] += dp[s - a]
    return dp[target]


def latin_square_grid(order=9):
    """A deterministic Latin square over {1..order}, two-digit zero-padded tiles."""
    rows = []
    for i in range(order):
        rows.append(" ".join("%02d" % ((i + j) % order + 1) for j in range(order)))
    return "\n".join(rows)


def overlap_runs(cfg):
    bstart = int(cfg.get("business_start", DEFAULTS["business_start"]))
    bend = int(cfg.get("business_end", DEFAULTS["business_end"]))
    lstart = int(cfg.get("lunch_start", DEFAULTS["lunch_start"]))
    lend = int(cfg.get("lunch_end", DEFAULTS["lunch_end"]))
    dur = int(cfg.get("duration_needed", DEFAULTS["duration_needed"]))
    busy = cfg.get("busy", {}) or {}

    intervals = []
    for _person, segs in busy.items():
        if not isinstance(segs, list):
            continue  # malformed per-person entry: ignore
        for seg in segs:
            if not isinstance(seg, (list, tuple)) or len(seg) < 2:
                continue
            try:
                s, e = int(seg[0]), int(seg[1])
            except (TypeError, ValueError):
                continue
            if e <= s:
                continue  # inverted/empty interval: occupies nothing
            intervals.append((s, e))

    def free(minute):
        if minute < bstart or minute >= bend:
            return False
        if lstart <= minute < lend:
            return False
        for (s, e) in intervals:
            if s <= minute < e:
                return False
        return True

    runs = []
    start = None
    for minute in range(bstart, bend):
        if free(minute):
            if start is None:
                start = minute
        else:
            if start is not None:
                runs.append((start, minute))
                start = None
    if start is not None:
        runs.append((start, bend))

    windows = [
        {"start": hhmm(s), "end": hhmm(e)}
        for (s, e) in runs
        if e - s >= dur
    ]
    return {
        "business": {"start": hhmm(bstart), "end": hhmm(bend)},
        "lunch": {"start": hhmm(lstart), "end": hhmm(lend)},
        "duration_needed": dur,
        "windows": windows,
    }


def main(config_path, outdir):
    with open(config_path, "r") as fh:
        cfg = json.load(fh)
    os.makedirs(outdir, exist_ok=True)

    allowed = cfg.get("allowed", [])
    if not isinstance(allowed, list):
        allowed = []
    target = cfg.get("target_sum", 0)
    ans = subset_sum_count(allowed, target)
    with open(os.path.join(outdir, "answer.txt"), "w") as fh:
        fh.write(str(ans))  # exactly the integer, no trailing newline

    with open(os.path.join(outdir, "grid.txt"), "w") as fh:
        fh.write(latin_square_grid() + "\n")

    with open(os.path.join(outdir, "plans.txt"), "w") as fh:
        json.dump(overlap_runs(cfg), fh, indent=2)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.stderr.write("usage: solver.py CONFIG.JSON OUTDIR\n")
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])