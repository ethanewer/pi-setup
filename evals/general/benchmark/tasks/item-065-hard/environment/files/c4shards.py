#!/usr/bin/env python3
"""Fine-tuned C4-shard pack/unpack tool — INCOMPLETE STUB (item-065-hard).

CLI scaffold only; pack/unpack must be implemented (see instruction.md).
Additional CLI flags over the medium task:
    pack ROOT OUT [--limit N] [--exclude GLOB]
--exclude drops any file whose relative path matches the glob expression
(directories are still recorded).
"""
import argparse
import os
import sys


def pack(root, bundle_out, limit=4096, exclude=None):
    raise NotImplementedError("pack() is not implemented yet")


def unpack(bundle_in, dest):
    raise NotImplementedError("unpack() is not implemented yet")


def main(argv=None):
    argv = argv if argv is not None else sys.argv[1:]
    ap = argparse.ArgumentParser(prog="c4shards")
    sub = ap.add_subparsers(dest="command", required=True)

    p = sub.add_parser("pack")
    p.add_argument("root")
    p.add_argument("bundle_out")
    p.add_argument("--limit", type=int, default=4096)
    p.add_argument("--exclude", action="append", default=[])

    u = sub.add_parser("unpack")
    u.add_argument("bundle_in")
    u.add_argument("dest")

    args = ap.parse_args(argv)
    if args.command == "pack":
        pack(args.root, args.bundle_out, limit=args.limit, exclude=args.exclude)
    else:
        unpack(args.bundle_in, args.dest)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())