#!/usr/bin/env python3
"""Severity-count reference for the willow-upland verifier.

Counts, across every `*.log` file in a directory, how many LINES carry each of
the severity tokens INFO/WARN/ERROR, where a token "carries" a line when it
appears as a standalone word (word chars = [A-Za-z0-9_]) case-insensitively.

This is used by tests/test.sh as the ground truth to compare against the
agent-produced /app/out/summary/severity_counts.txt. It deliberately mirrors
`grep -iw` behaviour (C-locale style word boundary) so a correct oracle agrees
with it on every fixture.

Usage:
    python3 severity_ref.py /path/to/logs
prints:
    INFO=<n>
    WARN=<n>
    ERROR=<n>
"""
import os
import sys

_WORD_CHARS = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
_TOKENS = ("INFO", "WARN", "ERROR")


def _has_word(line, token):
    low = line.lower()
    t = token.lower()
    n = len(t)
    i = 0
    while True:
        i = low.find(t, i)
        if i < 0:
            return False
        e = i + n
        before_ok = (i == 0) or (line[i - 1] not in _WORD_CHARS)
        after_ok = (e == len(line)) or (line[e] not in _WORD_CHARS)
        if before_ok and after_ok:
            return True
        i += 1


def count_severities(logdir):
    totals = {"INFO": 0, "WARN": 0, "ERROR": 0}
    if not os.path.isdir(logdir):
        return totals
    for fname in sorted(os.listdir(logdir)):
        path = os.path.join(logdir, fname)
        if os.path.isfile(path) and fname.endswith(".log"):
            try:
                text = open(path, errors="replace").read()
            except OSError:
                continue
            for line in text.split("\n"):
                for tok in _TOKENS:
                    if _has_word(line, tok):
                        totals[tok] += 1
    return totals


def render(totals):
    return "INFO=%d\nWARN=%d\nERROR=%d\n" % (
        totals["INFO"], totals["WARN"], totals["ERROR"])


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("usage: counts.py LOGDIR")
    sys.stdout.write(render(count_severities(sys.argv[1])))