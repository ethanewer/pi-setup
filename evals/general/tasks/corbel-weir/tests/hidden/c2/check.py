"""Hidden check c2: the installed wheel must power a chained group of
commands with typed options and defaulting, through the project's own
CliRunner."""
import sys

import click
from click.testing import CliRunner


@click.group(chain=True)
def cli():
    pass


@cli.command()
@click.option("--count", type=click.IntRange(1, 10), default=1)
def add(count):
    click.echo(f"add:{count}")


@cli.command()
def done():
    click.echo("done")


r = CliRunner().invoke(cli, ["add", "--count", "3", "done"])
if r.exit_code != 0:
    print(f"chain run exited {r.exit_code}: {r.output}", file=sys.stderr)
    sys.exit(1)
if r.output != "add:3\ndone\n":
    print(f"chain output = {r.output!r}", file=sys.stderr)
    sys.exit(1)

# defaulting must still work without the option
r2 = CliRunner().invoke(cli, ["add", "done"])
if r2.exit_code != 0 or r2.output != "add:1\ndone\n":
    print(f"defaulting output = {r2.output!r}", file=sys.stderr)
    sys.exit(1)

# IntRange must reject values outside [1, 10]
r3 = CliRunner().invoke(cli, ["add", "--count", "42", "done"])
if r3.exit_code == 0:
    print("IntRange accepted 42", file=sys.stderr)
    sys.exit(1)
print("c2 ok: chained group, typed options, defaults, range validation")