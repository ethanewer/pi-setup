#!/usr/bin/env python3
"""lintkit command line: load rule plugins, run them, apply suppressions.

Usage:
    lint.py [--stats] [--no-cache] [--cache-dir DIR] [--rules-dir DIR] FILE...

For every input FILE the engine:
  1. computes a synthetic cache key (rules signature + sha256 of the file
     bytes) and reuses a cached finding list when one exists;
  2. otherwise parses the file, runs every loaded rule plugin over the whole
     tree, applies the documented suppression directives, sorts the surviving
     findings and (unless caching is disabled) stores them in the cache dir.

stdout is a single JSON object mapping each input path to its sorted finding
array.  ``--stats`` additionally prints ``cache:key=value`` lines to stderr.
Exit code is 0 on success.

Rule plugins live in the rules dir (``.py`` files).  A module contributes one
or more rules; a rule is any class with both ``id`` (a non-empty str) and a
callable ``check(self, node, ctx)`` that returns a list of finding dicts
``{"id","line","col","message"}``.  ``ctx`` carries ``root`` (the parsed,
annotated Module), ``file`` (path), ``text`` (source) and ``rules_dir``.
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
from ast_nodes import Module  # noqa: E402

# ---------------------------------------------------------------------------
# Suppression directives
#
# A comment is a directive iff its body (text after '#', trimmed) matches one
# of these four forms.  Each may carry a comma-separated list of rule ids.
#   LINE  `nolint(<ids>)`            suppress on the comment's own line
#   REGION begin `nolint-begin(<ids>)` ... end `nolint-end(<ids>)`  suppress on
#         every line from begin through end (inclusive); an unclosed begin
#         extends to the last source line.
#   NEXT  `nolint:next(<ids>)`       suppress on the single line that is the
#         next statement's start line after the directive.
#
# A finding is suppressed iff ANY applicable directive suppresses it (line,
# region and next directives for its id all hide it; there is no re-enabling).
# ---------------------------------------------------------------------------

_DINT_RE = r"([A-Za-z0-9_-]+)"

_DIRECTIVES = (
    ("begin", re.compile(r"^nolint-begin\(([^)]*)\)$")),
    ("end", re.compile(r"^nolint-end\(([^)]*)\)$")),
    ("next", re.compile(r"^nolint:next\(([^)]*)\)$")),
    ("line", re.compile(r"^nolint\(([^)]*)\)$")),
)


def _ids(inner):
    out = []
    for part in inner.split(","):
        part = part.strip()
        if part and re.fullmatch(_DINT_RE, part):
            out.append(part)
    return out


def _scan_directives(text):
    """Return dicts: line_by_id, begin_by_id, end_by_id, next_by_id."""
    line_by = {}
    begin_by = {}
    end_by = {}
    next_by = {}
    for tok in tokenize(text):
        if tok[0] != "COMMENT":
            continue
        body = tok[1][1:].strip()
        line = tok[2]
        for kind, rx in _DIRECTIVES:
            m = rx.match(body)
            if not m:
                continue
            ids = _ids(m.group(1))
            if kind == "line":
                for rid in ids:
                    line_by.setdefault(rid, set()).add(line)
            elif kind == "begin":
                for rid in ids:
                    begin_by.setdefault(rid, []).append(line)
            elif kind == "end":
                for rid in ids:
                    end_by.setdefault(rid, []).append(line)
            elif kind == "next":
                for rid in ids:
                    next_by.setdefault(rid, []).append(line)
            break
    return line_by, begin_by, end_by, next_by


def _regions_for(rid, begin_by, end_by, last_line):
    """Stack-based region matching per id: an end closes the most recently
    opened, still-open begin of that id; an unclosed begin extends to the
    last source line.  Returns the union of all matched lines."""
    events = []
    for b in begin_by.get(rid, []):
        events.append((b, "begin"))
    for e in end_by.get(rid, []):
        events.append((e, "end"))
    events.sort()
    open_begins = []
    suppressed = set()
    for line, kind in events:
        if kind == "begin":
            open_begins.append(line)
        else:
            if open_begins:
                start = open_begins.pop()
                suppressed.update(range(start, line + 1))
    for start in open_begins:
        suppressed.update(range(start, last_line + 1))
    return suppressed


def _next_targets_for(rid, next_by, stmt_start_lines):
    starts = sorted(stmt_start_lines)
    targets = set()
    for n in next_by.get(rid, []):
        for s in starts:
            if s > n:
                targets.add(s)
                break
    return targets


def suppressed_lines(root, text):
    """Build {rule_id: set of lines} that are suppressed."""
    line_by, begin_by, end_by, next_by = _scan_directives(text)
    last_line = text.count("\n") + (0 if text.endswith("\n") else 1)
    if last_line < 1:
        last_line = 1
    supp = {}
    all_ids = set(line_by) | set(begin_by) | set(next_by)
    for rid in all_ids:
        lines = set(line_by.get(rid, ()))
        lines |= _regions_for(rid, begin_by, end_by, last_line)
        lines |= _next_targets_for(rid, next_by, root.stmt_start_lines)
        supp[rid] = lines
    return supp


# ---------------------------------------------------------------------------
# Rule loading
# ---------------------------------------------------------------------------

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
        except Exception as exc:  # a broken rule must not kill the run
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


# ---------------------------------------------------------------------------
# Findings
# ---------------------------------------------------------------------------

class Context(object):
    def __init__(self, root, file, text, rules_dir):
        self.root = root
        self.file = file
        self.text = text
        self.rules_dir = rules_dir


def findings_for_file(path, text, rules, rules_dir):
    root = build_context(parse(text, path))
    ctx = Context(root, path, text, rules_dir)
    cand = []
    for rule in rules:
        for node in all_nodes(root):
            cand.extend(rule.check(node, ctx))
    supp = suppressed_lines(root, text)
    surviving = [f for f in cand if f["line"] not in supp.get(f["id"], ())]
    surviving.sort(key=lambda f: (f["line"], f["col"], f["id"], f["message"]))
    return surviving


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main(argv=None):
    ap = argparse.ArgumentParser(
        prog="lint.py", description="lintkit linter CLI")
    ap.add_argument("--stats", action="store_true",
                    help="print cache statistics to stderr")
    ap.add_argument("--no-cache", action="store_true",
                    help="disable the finding cache")
    ap.add_argument("--cache-dir", default="/app/lintcache",
                    help="cache directory (default /app/lintcache)")
    ap.add_argument("--rules-dir", default="/app/rules",
                    help="rule plugin directory (default /app/rules)")
    ap.add_argument("files", nargs="+", help="minipy source files")
    args = ap.parse_args(argv)

    rules = load_rules(args.rules_dir)
    sig = rule_signature(rules)

    results = {}
    reused = []
    computed = []
    for path in args.files:
        with open(path, "r", encoding="utf-8") as fh:
            text = fh.read()
        ch = content_hash(text)
        entry = os.path.join(args.cache_dir, "%s_%s.json" % (sig, ch))
        if not args.no_cache and os.path.isfile(entry):
            with open(entry, "r", encoding="utf-8") as fh:
                findings = json.load(fh)
            reused.append(path)
        else:
            findings = findings_for_file(path, text, rules, args.rules_dir)
            if not args.no_cache:
                os.makedirs(args.cache_dir, exist_ok=True)
                with open(entry, "w", encoding="utf-8") as fh:
                    json.dump(findings, fh)
            computed.append(path)
        results[path] = findings

    json.dump(results, sys.stdout, sort_keys=False)
    sys.stdout.write("\n")

    if args.stats:
        sys.stderr.write("cache:dir=%s\n" % args.cache_dir)
        sys.stderr.write("cache:inputs=%d\n" % len(args.files))
        sys.stderr.write("cache:hits=%d\n" % len(reused))
        sys.stderr.write("cache:misses=%d\n" % len(computed))
        sys.stderr.write("cache:reused=%s\n" % ",".join(reused))
        sys.stderr.write("cache:computed=%s\n" % ",".join(computed))
    return 0


if __name__ == "__main__":
    sys.exit(main())
