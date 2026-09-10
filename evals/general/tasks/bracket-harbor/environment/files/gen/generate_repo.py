#!/usr/bin/env python3
"""Deterministic stage-based generator for the bh-domain Go repository.

Usage: python3 generate_repo.py --stage <stage> --out <dir>
Writes the full tree as of <stage>. Stages are cumulative; op.go's precedence
table flips to the buggy consolidated-tier form from stage "refactor" on.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from pkgs import root as mod_root
from pkgs import version as mod_version
from pkgs import token as mod_token
from pkgs import lexer as mod_lexer
from pkgs import ast as mod_ast
from pkgs import parser as mod_parser
from pkgs import store as mod_store
from pkgs import idx as mod_idx
from pkgs import schema as mod_schema
from pkgs import query as mod_query
from pkgs import report as mod_report
from pkgs import conf as mod_conf
from pkgs import cmd as mod_cmd

STAGE_ORDER = [
    "base", "version", "token", "lexer", "ast", "parser", "store", "idx",
    "schema", "query", "report", "conf", "cmd", "planner", "refactor",
    "reportal", "head",
]

MODULES = [
    mod_root, mod_version, mod_token, mod_lexer, mod_ast, mod_parser,
    mod_store, mod_idx, mod_schema, mod_query, mod_report, mod_conf, mod_cmd,
]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stage", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    if args.stage not in STAGE_ORDER:
        raise SystemExit("unknown stage %r" % args.stage)
    my_idx = STAGE_ORDER.index(args.stage)

    merged = {}
    for m in MODULES:
        for rel, (intro, factory) in m.FILES.items():
            if rel in merged:
                raise SystemExit("duplicate file %s" % rel)
            merged[rel] = (intro, factory)

    buggy = args.stage in ("refactor", "reportal", "head")
    n_written = 0
    n_lines = 0
    for rel, (intro, factory) in sorted(merged.items()):
        if STAGE_ORDER.index(intro) > my_idx:
            continue
        content = factory(args.stage, buggy)
        if content is None:
            continue
        path = os.path.join(args.out, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(content)
        n_written += 1
        n_lines += content.count("\n")
    print("stage %s: wrote %d files, %d lines" % (args.stage, n_written, n_lines))


if __name__ == "__main__":
    main()