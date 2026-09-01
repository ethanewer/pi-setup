#!/usr/bin/env python3
"""flint call-site grouper.

A call site is identified by the top three innermost frames of a stack
sample (the innermost frame is the first token on the line). Samples with
fewer than three frames contribute a site equal to their full frame list.
Groups identical sites and prints the top-10 sites by descending count with
ties broken by ascending key.

Usage:  python3 callsites.py SAMPLE_FILE
"""
import collections
import sys


def frames_of(line):
    return [t for t in line.strip().split(";") if t != ""]


def key_of(frames):
    # top three innermost frames; fewer frames use all available top frames
    return ";".join(frames[:3])


def main(argv):
    path = argv[1] if len(argv) > 1 else "/app/samples/traces.txt"
    counts = collections.Counter()
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            if not line.strip():
                continue
            counts[key_of(frames_of(line))] += 1
    sites = sorted(counts.items(), key=lambda kv: (-kv[1], kv[0]))
    for key, cnt in sites[:10]:
        print(cnt, key)


if __name__ == "__main__":
    main(sys.argv)
