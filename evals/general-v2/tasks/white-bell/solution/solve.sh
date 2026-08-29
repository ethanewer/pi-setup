#!/bin/bash
set -eu
cat > /app/query.py <<'PY'
#!/usr/bin/env python3
"""Conjunctive graph-pattern query engine.

Given `triples.json` (list of [s,p,o] triples) and `query.txt` (one pattern of
three space-separated tokens per line, `?var`-prefixed tokens are variables),
write every distinct full variable binding satisfying all patterns to
`query_result.json` next to the queried input files.

Output shape:
    {"join_order": "a,b,c", "bindings": [{"a": "...", ...}, ...]}
"""
import json
import os
from itertools import product


def load():
    with open("triples.json", "r", encoding="utf-8") as fh:
        triples = [[str(v) for v in t] for t in json.load(fh)]
    patterns = []
    with open("query.txt", "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line:
                continue
            pat = line.split()
            if len(pat) != 3:
                raise ValueError("pattern must have exactly 3 tokens: %r" % line)
            patterns.append(pat)
    return triples, patterns


def _is_var(tok):
    return tok.startswith("?")


def _var(tok):
    return tok[1:]


def collect_variables(patterns):
    seen = []
    for pat in patterns:
        for tok in pat:
            if _is_var(tok) and _var(tok) not in seen:
                seen.append(_var(tok))
    return seen


def pattern_match(triple, pattern):
    """Partial binding if a single triple lines up with a pattern, else None."""
    binding = {}
    for tok, val in zip(pattern, triple):
        if _is_var(tok):
            binding[_var(tok)] = val
        elif tok != val:
            return None
    return binding


def pattern_holds(triples, pattern, full_binding):
    """Full binding satisfies the pattern if some triple agrees on all variables."""
    for triple in triples:
        part = pattern_match(triple, pattern)
        if part is None:
            continue
        if all(part.get(k, v) == v for k, v in full_binding.items()):
            return True
    return False


def solve(triples, patterns):
    variables = collect_variables(patterns)

    if not variables:
        if all(pattern_holds(triples, p, {}) for p in patterns):
            return [{}]
        return []

    domains = {}
    for pat in patterns:
        for triple in triples:
            part = pattern_match(triple, pat)
            if part is not None:
                for k, v in part.items():
                    domains.setdefault(k, set()).add(v)

    for v in variables:
        if v not in domains:
            return []

    ordered = sorted(variables)
    results = []
    for combo in product(*(sorted(domains[v]) for v in ordered)):
        binding = dict(zip(ordered, combo))
        if all(pattern_holds(triples, p, binding) for p in patterns):
            results.append(binding)
    results.sort(key=lambda b: tuple(b[v] for v in ordered))
    return results


def main():
    triples, patterns = load()
    variables = collect_variables(patterns)
    bindings = solve(triples, patterns)
    out = {
        "join_order": ",".join(variables),
        "bindings": [dict(sorted(b.items())) for b in bindings],
    }
    with open("query_result.json", "w", encoding="utf-8") as fh:
        json.dump(out, fh, indent=2)


if __name__ == "__main__":
    main()
PY
chmod +x /app/query.py
cd /app && python3 query.py
