#!/usr/bin/env python3
"""Fetch the live learning-leaderboard HTML page at runtime, compute the mean
score per org/model over the numeric columns, and emit the org/model identifier
of the row with the highest mean as a single trimmed line.

Writes /app/leaderboard_top.txt and prints the same identifier to stdout.
"""
import re
import sys
from urllib.request import urlopen

OUT = "/app/leaderboard_top.txt"


def strip_tags(s):
    return re.sub(r"<[^>]*>", "", s or "").strip()


def parse_rows(html):
    rows = re.findall(r"<tr[^>]*>(.*?)</tr>", html, re.S | re.I)
    out = []
    for row in rows:
        cells = [strip_tags(c) for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", row, re.S | re.I)]
        if len(cells) < 2:
            continue
        name = cells[0]
        if name.lower() in ("organization", "org/model", ""):
            continue
        numeric = []
        for c in cells[1:]:
            try:
                numeric.append(float(c))
            except ValueError:
                pass
        if not numeric:
            continue
        out.append((name, sum(numeric) / len(numeric)))
    return out


def top(html):
    rows = parse_rows(html)
    rows.sort(key=lambda t: (-t[1], t[0]))
    return rows[0][0][:200]


def main(argv):
    url = argv[0] if argv else None
    if not url:
        sys.stderr.write("usage: fetch_leaderboard.py <url>\n")
        return 2
    with urlopen(url, timeout=30) as resp:
        html = resp.read().decode("utf-8", "replace")
    item = top(html)
    with open(OUT, "w") as f:
        f.write(item + "\n")
    print(item)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))