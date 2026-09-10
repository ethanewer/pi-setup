"""Hidden check c1: the installed wheel must report the exact release version,
both through the metadata API and from a real CLI's --version flag."""
import sys

import click
from click.testing import CliRunner

import importlib.metadata as im

if im.version("click") != "8.5.0":
    print(f"importlib.metadata.version = {im.version('click')!r}",
          file=sys.stderr)
    sys.exit(1)


@click.command()
@click.version_option(prog_name="click", package_name="click")
def cli():
    pass


r = CliRunner().invoke(cli, ["--version"])
if r.exit_code != 0:
    print(f"version_option exited {r.exit_code}: {r.output}", file=sys.stderr)
    sys.exit(1)
if r.output.strip() != "click, version 8.5.0":
    print(f"version output = {r.output!r}", file=sys.stderr)
    sys.exit(1)
print("c1 ok: version metadata and --version output are 8.5.0")