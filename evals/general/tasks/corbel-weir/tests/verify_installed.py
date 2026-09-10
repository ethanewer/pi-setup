"""corbel-weir verifier helper: assert the INSTALLED wheel (never the source
tree) is the click 8.5.0 release.

Importable only with a venv whose site-packages hold the agent's wheel; the
helper is executed with cwd=/tmp so no checkout path is importable.
"""
import hashlib
import importlib.metadata as im
import pathlib
import sys

import click

upstream_sha = sys.argv[1]

# --- exact release metadata ------------------------------------------------
md = im.metadata("click")
expect = {
    "Name": "click",
    "Version": "8.5.0",
    "Requires-Python": ">=3.10",
    "License-Expression": "BSD-3-Clause",
    "License-File": "LICENSE.txt",
}
for field, want in expect.items():
    got = md.get(field)
    if got != want:
        print(f"metadata {field} = {got!r}, want {want!r}", file=sys.stderr)
        sys.exit(1)

# --- the installed package's own version wiring ----------------------------
if click.__version__ != "8.5.0":
    print(f"click.__version__ = {click.__version__!r}", file=sys.stderr)
    sys.exit(1)

# --- public entry points resolve from the installed wheel ------------------
for name in (
    "command", "group", "option", "argument", "echo", "confirm",
    "version_option", "IntRange", "Choice", "get_current_context",
):
    if not hasattr(click, name):
        print(f"public entry point click.{name} missing", file=sys.stderr)
        sys.exit(1)
from click.testing import CliRunner  # noqa: E402

# --- upstream identity: wheel code is byte-identical to the checkout -------
src_root = pathlib.Path("/app/src/src/click")
inst_root = pathlib.Path(click.__file__).parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


for mod in ("utils.py", "core.py", "decorators.py"):
    up, ins = src_root / mod, inst_root / mod
    if not up.is_file() or not ins.is_file():
        print(f"module {mod} missing on one side", file=sys.stderr)
        sys.exit(1)
    if sha(up) != sha(ins):
        print(f"wheel module {mod} differs from the upstream checkout",
              file=sys.stderr)
        sys.exit(1)

print("verify_installed: metadata, entry points, upstream identity OK")