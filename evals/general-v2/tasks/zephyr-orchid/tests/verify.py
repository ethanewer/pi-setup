#!/usr/bin/env python3
"""tests/verify.py — transcript normaliser used by test.sh (hidden ASR checks).

normalise() must match the contract in instruction.md:
  lowercase; replace every non [a-z0-9 ] character with a single space; collapse
  runs of whitespace to one space; trim.
A transcript (file of one line) is correct iff norm(got) == norm(expected).
"""
import argparse


def normalise(text: str) -> str:
    out = []
    for ch in text.lower():
        out.append(ch if (ch.isalnum() or ch == " ") else " ")
    return " ".join("".join(out).split())


def read(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("transcript_file", help="agent-produced transcript file")
    ap.add_argument("expected", help="expected plain transcript text")
    ap.add_argument("--echo", action="store_true", help="also print both")
    args = ap.parse_args()
    got = read(args.transcript_file)
    ok = normalise(got) == normalise(args.expected)
    if args.echo:
        print(f"got     : {got.strip()!r}")
        print(f"norm(got): {normalise(got)!r}")
        print(f"norm(exp): {normalise(args.expected)!r}")
    print("MATCH" if ok else "MISMATCH")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())