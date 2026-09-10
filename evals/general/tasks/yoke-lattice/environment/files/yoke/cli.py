"""yoke.cli — command line interface.

Subcommands:

  lint <paths...>   style gate: trailing whitespace, tabs, CRLF, merge
                    markers, plus .grid files that fail to parse.
  build             assemble dist/yoke-<version>.tar.gz reproducibly.
  render <file>     print a .grid file with its yokes annotated.
"""

import argparse
import io
import os
import sys
import tarfile

from . import __version__
from .lattice import Grid, GridError

MERGE_MARKERS = ("<<<<<<<", "=======", ">>>>>>>")

SKIP_DIRS = {"__pycache__", ".git", "dist", ".pytest_cache", ".venv",
             "node_modules"}
SKIP_SUFFIXES = (".pyc", ".pyo", ".so")


def _iter_files(paths):
    """Yield regular files under the given paths, directories walked."""
    for path in paths:
        if os.path.isdir(path):
            for root, dirs, files in os.walk(path):
                dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS)
                for fn in sorted(files):
                    if not fn.endswith(SKIP_SUFFIXES):
                        yield os.path.join(root, fn)
        elif os.path.isfile(path):
            yield path


def _check_style(path, problems):
    try:
        with open(path, "r", encoding="utf-8", newline="") as fh:
            lines = fh.readlines()
    except OSError as e:
        problems.append("%s: unreadable: %s" % (path, e))
        return 1
    except UnicodeDecodeError as e:
        problems.append("%s: not utf-8 text: %s" % (path, e))
        return 1
    bad = 0
    for i, ln in enumerate(lines, 1):
        body = ln.rstrip("\n").rstrip("\r")
        if ln.endswith("\r\n"):
            problems.append("%s:%d: CRLF line ending" % (path, i))
            bad += 1
        if "\t" in body:
            problems.append("%s:%d: tab character" % (path, i))
            bad += 1
        if body != body.rstrip():
            problems.append("%s:%d: trailing whitespace" % (path, i))
            bad += 1
        if body.lstrip().startswith(MERGE_MARKERS):
            problems.append("%s:%d: unresolved merge marker" % (path, i))
            bad += 1
    if path.endswith(".grid"):
        try:
            Grid.parse("".join(lines))
        except GridError as e:
            problems.append("%s: not a valid grid: %s" % (path, e))
            bad += 1
    return bad


def cmd_lint(args, problems):
    total = 0
    for path in _iter_files(args.paths):
        total += _check_style(path, problems)
    return total


def cmd_build(args, problems):
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    dist = os.path.join(here, "dist")
    os.makedirs(dist, exist_ok=True)
    arcname = "yoke-%s" % __version__
    target = os.path.join(dist, arcname + ".tar.gz")
    tmp = target + ".tmp"
    with tarfile.open(tmp, "w:gz") as tf:
        for rel in ("yoke/__init__.py", "yoke/lattice.py", "yoke/cli.py",
                    "README.md", "Makefile", "pyproject.toml"):
            p = os.path.join(here, rel)
            if os.path.exists(p):
                tf.add(p, arcname=arcname + "/" + rel)
    os.replace(tmp, target)
    print(target)
    return 0


def cmd_render(args, problems):
    try:
        with open(args.file, "r", encoding="utf-8") as fh:
            grid = Grid.parse(fh.read())
    except OSError as e:
        problems.append("cannot read %s: %s" % (args.file, e))
        return 1
    except GridError as e:
        problems.append("%s: %s" % (args.file, e))
        return 1
    print(grid.render())
    print("yokes: %s" % (", ".join("%d=%s" % (r, c) for r, c in grid.yokes())
                         or "none"))
    return 0


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    ap = argparse.ArgumentParser(prog="yoke", description=__doc__)
    ap.add_argument("--version", action="store_true")
    sub = ap.add_subparsers(dest="command", required=True)

    p_lint = sub.add_parser("lint", help="run the style gate on paths")
    p_lint.add_argument("paths", nargs="+")

    sub.add_parser("build", help="assemble the distribution tarball")

    p_render = sub.add_parser("render", help="render a .grid file")
    p_render.add_argument("file")

    args = ap.parse_args(argv)
    if getattr(args, "version", False):
        print(__version__)
        return 0
    problems = []
    code = {"lint": cmd_lint, "build": cmd_build, "render": cmd_render}[
        args.command](args, problems)
    for p in problems:
        print(p, file=sys.stderr)
    return 1 if code else 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())