#!/usr/bin/env python3
"""Confirm every version constraint in a pip-requirements-style manifest.

Usage:
    python3 confirm_versions.py <MANIFEST>

Reads <MANIFEST> and for every named distribution checks the version installed
in the environment that RUNS this script (importlib.metadata). If every named
dist is present and satisfies every specifier, exit 0; otherwise print one
informational line per problem and exit 1.

Deterministic handling of edge / malformed input (documented in instruction):
  - blank lines, lines starting with '#', and text after '#' are ignored;
  - lines starting with '-' (e.g. '-r other.txt', '--index-url ...') are skipped
    without being opened, with an INFO line;
  - a line with no version operator is a bare package name and only needs to be
    installed to pass;
  - supported operators: ==  ===  !=  >=  <=  >  <  ~=  and the '==X.Y.*'
    wildcard, plus comma-joined combined specs such as 'numpy>=1.24,<2.0';
  - unparseable specifiers are reported as ERROR/MISMATCH, never raised to
    stderr.
"""

import importlib.metadata as md
import re
import sys

OP_RE = re.compile(r"""(?x)
    ^\s*(?P<op>===|==|!=|>=|<=|~=|>|<)\s*(?P<v>.*?)\s*$
""")


def _nums(s):
    return tuple(int(x) for x in re.findall(r"\d+", s))


def _cmp(t, u):
    t = t + (0,) * max(0, len(u) - len(t))
    u = u + (0,) * max(0, len(t) - len(u))
    return (t > u) - (t < u)


def _satisfy(installed, spec):
    spec = spec.strip()
    if not spec:
        raise ValueError("empty specifier")
    if spec == "*":
        return True
    m = OP_RE.match(spec)
    if not m:
        raise ValueError(f"unparseable specifier: {spec!r}")
    op, rest = m.group("op"), m.group("v").strip()
    if rest.endswith(".*"):
        base = _nums(rest[:-2])
        # '==X.Y.*' matches any installed version sharing prefix X.Y
        return op in ("==", "===") and installed[: len(base)] == base
    rn = _nums(rest)
    if len(rn) == 0:
        raise ValueError(f"specifier with no version: {spec!r}")
    if op == "==":
        return installed[: len(rn)] == rn  # fewer components = prefix match
    if op == "===":
        return installed == rn
    if op == "!=":
        return installed[: len(rn)] != rn
    if op == ">=":
        return _cmp(installed, rn) >= 0
    if op == "<=":
        return _cmp(installed, rn) <= 0
    if op == ">":
        return _cmp(installed, rn) > 0
    if op == "<":
        return _cmp(installed, rn) < 0
    if op == "~=":
        return _cmp(installed, rn) >= 0 and installed[: len(rn) - 1] == rn[:-1]
    raise ValueError(f"unsupported operator: {op!r}")


def main():
    if len(sys.argv) < 2:
        print("usage: confirm_versions.py <MANIFEST>", file=sys.stderr)
        return 2
    manifest = sys.argv[1]
    rc = 0
    with open(manifest, encoding="utf-8", errors="replace") as fh:
        for lineno, raw in enumerate(fh):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("-"):
                print(f"INFO line {lineno}: skipped option/ref {line.split()[0]}")
                continue
            if "#" in line:
                line = line[: line.index("#")].strip()
            # separate a leading package name from its constraints
            nm = re.match(r"^([^=<>!~]+)", line)
            name = nm.group(1).strip() if nm else line
            name = name.replace("_", "-")
            rest = line[len(name):].strip()
            # strip any stray leading operators left around name (`>=pkg`)
            # (a name containing a '.' from a path is treated as a name token)
            if not name:
                continue
            try:
                installed_str = md.version(name)
            except md.PackageNotFoundError:
                print(f"MISSING {name}")
                rc = 1
                continue
            installed = _nums(installed_str)
            word = re.sub(r"^\s*[\s:]+", "", rest)
            if not word:
                print(f"OK {name} {installed_str}")  # bare name, presence enough
                continue
            ok = True
            for part in word.split(","):
                part = part.strip()
                if not part:
                    continue
                try:
                    if not _satisfy(installed, part):
                        ok = False
                except ValueError as e:
                    print(f"ERROR {name} {installed_str} <- {line} ({e})")
                    ok = False
                    rc = 1
            if ok:
                print(f"OK {name} {installed_str}")
            else:
                print(f"MISMATCH {name} {installed_str} <- {line}")
                rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())