#!/usr/bin/env python3
"""
Quartz Grove dependency resolver.

Reads a dependency spec JSON (`--spec PATH`) describing a target library
("interface", normally numpy), the candidate versions of that interface, a
catalogue mapping each dependent package to the package-version it ships for
various interface ranges, and a list of modules (dependents) each of whom
constrains the interface to a range.

The resolver's job is to produce ONE consistent pinned set: the HIGHEST
candidate interface version that simultaneously satisfies every module's
interface range AND for which every module's package has a compatible catalogue
entry.

Exit contract (this is the documented, testable behaviour):
  * success (a consistent set exists)
        -> print one JSON lock to stdout, exit 0
  * malformed spec (bad JSON, bad tokens, unknown package, empty candidates...)
        -> nothing on stdout, one stderr line, exit 1
  * structurally valid but NO candidate satisfies all modules (a conflict)
        -> nothing on stdout, one stderr line, exit 2
"""
import argparse
import json
import re
import sys

VERSION_RE = re.compile(r"^[0-9]+(?:\.[0-9]+)*$")
TOKEN_RE = re.compile(r"^(>=|<=|>|<|==)[0-9]+(?:\.[0-9]+)*$")


def virt(vstr):
    """Dotted version -> comparable tuple of ints."""
    return tuple(int(p) for p in vstr.split("."))


def vcmp(a, b):
    x, y = virt(a), virt(b)
    return (x > y) - (x < y)


def parse_range(expr):
    """Return a list of (op, target) tokens, or None if the range is malformed."""
    if not isinstance(expr, str):
        return None
    tokens = [t.strip() for t in expr.split(",") if t.strip()]
    if not tokens:
        return None
    out = []
    for tok in tokens:
        m = TOKEN_RE.match(tok)
        if not m:
            return None
        op = m.group(1)
        target = tok[len(op):]
        if not VERSION_RE.match(target):
            return None
        out.append((op, target))
    return out


def token_ok(version, op, target):
    c = vcmp(version, target)
    if op == ">=":
        return c >= 0
    if op == "<=":
        return c <= 0
    if op == ">":
        return c > 0
    if op == "<":
        return c < 0
    return c == 0  # "=="


def range_ok(version, tokens):
    return all(token_ok(version, op, target) for (op, target) in tokens)


def malformed(reason):
    sys.stderr.write(f"malformed spec: {reason}\n")
    sys.exit(1)


def conflict(reason):
    sys.stderr.write(f"conflict: {reason}\n")
    sys.exit(2)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--spec", required=True)
    args = ap.parse_args()

    try:
        with open(args.spec) as fh:
            spec = json.load(fh)
    except Exception as exc:
        malformed("cannot load spec: %s" % exc)

    if not isinstance(spec, dict):
        malformed("spec must be a JSON object")

    candidates = spec.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        malformed("candidates must be a non-empty list")
    for cand in candidates:
        if not isinstance(cand, str) or not VERSION_RE.match(cand):
            malformed("bad candidate version: %r" % (cand,))

    catalogue = spec.get("catalogue")
    if not isinstance(catalogue, dict):
        malformed("catalogue must be an object")
    for pkg, entries in catalogue.items():
        if not isinstance(entries, list) or not entries:
            malformed("package %r must map to a non-empty list" % (pkg,))
        seen = set()
        for e in entries:
            if not isinstance(e, dict) or "numpy" not in e or "version" not in e:
                malformed("bad catalogue entry for %r" % (pkg,))
            if parse_range(e.get("numpy")) is None:
                malformed("bad catalogue numpy range for %r" % (pkg,))
            if not isinstance(e["version"], str) or not VERSION_RE.match(e["version"]):
                malformed("bad catalogue version for %r" % (pkg,))
            if e["version"] in seen:
                malformed("duplicate catalogue version for %r" % (pkg,))
            seen.add(e["version"])

    modules = spec.get("modules")
    if not isinstance(modules, list) or not modules:
        malformed("modules must be a non-empty list")
    names = set()
    for m in modules:
        if not isinstance(m, dict):
            malformed("each module must be an object")
        for key in ("name", "package", "numpy"):
            if not isinstance(m.get(key), str) or not m[key]:
                malformed("module missing string field %r" % (key,))
        if m["name"] in names:
            malformed("duplicate module name %r" % (m["name"],))
        names.add(m["name"])
        if m["package"] not in catalogue:
            malformed("module %r references unknown package %r" % (m["name"], m["package"]))
        if parse_range(m["numpy"]) is None:
            malformed("bad numpy range on module %r" % (m["name"],))

    # NEWEST candidate satisfying every module's range AND covered by the
    # catalogue for every module's package.
    chosen = None
    for cand in sorted(candidates, key=virt, reverse=True):
        ok = True
        for m in modules:
            if not range_ok(cand, parse_range(m["numpy"])):
                ok = False
                break
            entries = catalogue[m["package"]]
            if not any(range_ok(cand, parse_range(e["numpy"])) for e in entries):
                ok = False
                break
        if ok:
            chosen = cand
            break

    if chosen is None:
        conflict("no candidate interface version satisfies all module constraints")

    mods = {}
    for m in modules:
        entries = catalogue[m["package"]]
        compatible = [e for e in entries if range_ok(chosen, parse_range(e["numpy"]))]
        if not compatible:
            conflict("module %r has no package compatible with numpy %s" % (m["name"], chosen))
        best = max(compatible, key=lambda e: virt(e["version"]))
        mods[m["name"]] = {"package": m["package"], "version": best["version"]}

    lock = {
        "interface": spec.get("interface", "numpy"),
        "numpy": chosen,
        "modules": mods,
        "consistent": True,
    }
    sys.stdout.write(json.dumps(lock) + "\n")
    sys.exit(0)


if __name__ == "__main__":
    main()