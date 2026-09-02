#!/usr/bin/env python3
"""rank_callsites.py — aggregate & rank call-site signatures (prism part 1).

Usage:
    python3 rank_callsites.py <input_dir> <output_path> [top_n]

Reads every regular file directly inside <input_dir> (non-recursive, any
extension). Each text line is one call-site signature. Counting rules:
  * a line's trailing CR, trailing whitespace and leading whitespace are
    stripped before it is treated as a signature;
  * empty lines / whitespace-only lines are ignored (never counted).
Signatures are then ranked frequency-desc; equal counts are broken by the
signature text in ascending lexicographic (byte) order. The top <top_n>
(default 10) entries are written to <output_path> one signature per line,
each followed by a newline. If <top_n> exceeds the number of distinct
signatures, every distinct signature is written.
"""
import os
import sys


def scan(input_dir: str):
    """Yield the stripped text of every nonempty line in the directory."""
    try:
        names = [n for n in os.listdir(input_dir)
                 if os.path.isfile(os.path.join(input_dir, n))]
    except OSError:
        names = []
    names.sort()  # deterministic file iteration order
    for name in names:
        path = os.path.join(input_dir, name)
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            for raw in fh:
                line = raw.rstrip("\r\n").strip()
                if line:
                    yield line


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: rank_callsites.py INPUT_DIR OUTPUT [N]\n")
        return 2
    in_dir, out_path = argv[0], argv[1]
    top_n = int(argv[2]) if len(argv) > 2 else 10

    counts = {}
    for sig in scan(in_dir):
        counts[sig] = counts.get(sig, 0) + 1

    ranked = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    ranked = ranked[:top_n]

    with open(out_path, "w") as fh:
        for sig, _ in ranked:
            fh.write(sig + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))