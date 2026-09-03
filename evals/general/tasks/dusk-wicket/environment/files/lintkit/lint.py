#!/usr/bin/env python3
"""lintkit command line (SKELETON): load rule plugins, run them, apply
line-scoped suppressions.

This shipped skeleton already wires up rule loading + the CLI + the original
line-scoped suppression directive.  Your engineering work (see the task
brief) is to EXTEND it with:

  1. the region form   ``# nolint-begin(<ids>)`` ... ``# nolint-end(<ids>)``
     (unclosed begin extends to the last source line);
  2. the next-statement form ``# nolint:next(<ids>)`` which suppresses on the
     single line equal to the next statement's start line after the comment;
  3. an incremental findings cache under ``/app/lintcache`` keyed by
     ``sha256(sorted rule ids)`` + ``sha256(file bytes)``, plus a ``--stats``
     flag that prints ``cache:key=value`` lines to stderr.

Suppression precedence (documented): a finding is suppressed when ANY
applicable directive (line, region, next) for its id hides its anchor line;
there is no re-enabling.  stdout is one JSON object mapping input paths to
their sorted finding arrays; exit code 0 on success.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from lexer import tokenize  # noqa: E402
from parser import parse  # noqa: E402
from analyze import build_context, all_nodes  # noqa: E402

_DINT_RE = r"([A-Za-z0-9_-]+)"


def _ids(inner):
    out = []
    for part in inner.split(","):
        part = part.strip()
        if part and re.fullmatch(_DINT_RE, part):
            out.append(part)
    return out


def _scan_directives(text):
    """Currently implemented: the LINE form only.

    Returns {rule_id: set( lines )} of suppressed lines.
    TODO(agent): also scan nolint-begin / nolint-end regions and the
    nolint:next form per the documented semantics.
    """
    line_by = {}
    for tok in tokenize(text):
        if tok[0] != "COMMENT":
            continue
        m = re.match(r"^nolint\(([^)]*)\)$", tok[1][1:].strip())
        if not m:
            continue
        for rid in _ids(m.group(1)):
            line_by.setdefault(rid, set()).add(tok[2])
    return line_by


def suppressed_lines(root, text):
    """Build {rule_id: set( lines )} of suppressed lines."""
    return _scan_directives(text)


# -- rule loading -------------------------------------------------------

def load_rules(rules_dir):
    rules = []
    if not os.path.isdir(rules_dir):
        return rules
    for fname in sorted(os.listdir(rules_dir)):
        if not fname.endswith(".py"):
            continue
        path = os.path.join(rules_dir, fname)
        spec = importlib.util.spec_from_file_location(
            "rule_" + fname[:-3], path)
        if spec is None or spec.loader is None:
            continue
        mod = importlib.util.module_from_spec(spec)
        try:
            spec.loader.exec_module(mod)
        except Exception as exc:
            sys.stderr.write("warning: failed to load %s: %s\n" % (fname, exc))
            continue
        for attr in dir(mod):
            obj = getattr(mod, attr)
            if not isinstance(obj, type):
                continue
            rid = getattr(obj, "id", None)
            check = getattr(obj, "check", None)
            if isinstance(rid, str) and rid and callable(check):
                try:
                    rules.append(obj())
                except Exception as exc:
                    sys.stderr.write("warning: bad rule %s: %s\n" % (attr, exc))
    return rules


def rule_signature(rules):
    ids = "\n".join(sorted(r.id for r in rules))
    return hashlib.sha256(ids.encode("utf-8")).hexdigest()


def content_hash(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# -- findings ------------------------------------------------------------

class Context(object):
    def __init__(self, root, file, text, rules_dir):
        self.root = root
        self.file = file
        self.text = text
        self.rules_dir = rules_dir


def findings_for_file(path, text, rules):
    root = build_context(parse(text, path))
    ctx = Context(root, path, text, os.path.dirname(path))
    cand = []
    for rule in rules:
        for node in all_nodes(root):
            cand.extend(rule.check(node, ctx))
    supp = suppressed_lines(root, text)
    surviving = [f for f in cand if f["line"] not in supp.get(f["id"], ())]
    surviving.sort(key=lambda f: (f["line"], f["col"], f["id"], f["message"]))
    return surviving


# -- CLI ------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="lint.py", description="lintkit linter CLI")
    ap.add_argument("files", nargs="+", help="minipy source files")
    args = ap.parse_args(argv)

    rules = load_rules("/app/rules")
    results = {}
    for path in args.files:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
        results[path] = findings_for_file(path, text, rules)

    json.dump(results, sys.stdout, sort_keys=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())