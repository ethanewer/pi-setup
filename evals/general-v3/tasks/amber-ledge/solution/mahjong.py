#!/usr/bin/env python3
"""Atlas-core mahjong hand classifier.

Recognises two special winning patterns among the 34 tile types:
  - seven_pairs     : the hand is exactly seven pairs (14 tiles, every tile's
                      count is exactly 2).
  - thirteen_orphans: the hand uses exactly the 13 orphan tiles (terminals of
                      the three suits plus the four winds and three dragons)
                      with every orphan present at least once, and exactly one
                      tile appearing twice (total 14 tiles).
  - neither         : any other 14-tile hand.
  - malformed       : not exactly 14 tiles, or a tile outside the tile set.

Tiles are encoded as 2-char codes:
  suited: 1m..9m, 1p..9p, 1s..9s
  winds : e, s, w, n        dragons: R, G, B

CLI:
    python3 mahjong.py <path>
  <path> is either a single hand file or a directory of hand files.
  Every *.json file under the path is evaluated (recursively).

Single file        -> prints one JSON line: {"file": <name>, "pattern": <p>}
Directory          -> prints one JSON array of {"file","pattern"} sorted by name

Pattern labels: seven_pairs | thirteen_orphans | neither | malformed
"""

import os
import sys
import json

SUITED_M = ["%dm" % i for i in range(1, 10)]
SUITED_P = ["%dp" % i for i in range(1, 10)]
SUITED_S = ["%ds" % i for i in range(1, 10)]
WINDS = ["East", "South", "West", "North"]
DRAGONS = ["R", "G", "B"]
ALL_TILES = frozenset(SUITED_M + SUITED_P + SUITED_S + WINDS + DRAGONS)
ORPHANS = frozenset(["1m", "9m", "1p", "9p", "1s", "9s"] + WINDS + DRAGONS)


def classify(hand):
    """Return the winning-pattern label for `hand` (a list of tile codes)."""
    if not isinstance(hand, list) or len(hand) != 14:
        return "malformed"
    for t in hand:
        if not isinstance(t, str) or t not in ALL_TILES:
            return "malformed"
    counts = {}
    for t in hand:
        counts[t] = counts.get(t, 0) + 1
    # seven pairs: every distinct tlv appears exactly twice
    if all(v == 2 for v in counts.values()):
        return "seven_pairs"
    # thirteen orphans: only orphans, all present, exactly one doubled
    if len(counts) == 13 and all(k in ORPHANS for k in counts):
        if sum(1 for v in counts.values() if v == 2) == 1 and \
           all(v in (1, 2) for v in counts.values()):
            return "thirteen_orphans"
    return "neither"


def hand_from_file(path):
    import json
    with open(path, "r", encoding="utf-8") as fh:
        return json.load(fh)


def collect_files(path):
    if os.path.isfile(path):
        return [path]
    files = []
    for root, _dirs, names in os.walk(path):
        for n in sorted(names):
            if n.endswith(".json"):
                files.append(os.path.join(root, n))
    return sorted(files)


def evaluate_path(path):
    result = []
    for f in collect_files(path):
        hand = hand_from_file(f)
        result.append({"file": os.path.basename(f), "pattern": classify(hand)})
    return result


def main():
    path = sys.argv[1]
    res = evaluate_path(path)
    if os.path.isfile(path):
        sys.stdout.write(json.dumps(res[0]) + "\n")
    else:
        sys.stdout.write(json.dumps(res) + "\n")


if __name__ == "__main__":
    main()