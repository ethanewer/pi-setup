"""Hidden check c3: the installed wheel must power interactive confirmations,
choice coercion, and filename formatting through the project's own runner."""
import sys

import click
from click.testing import CliRunner


@click.command()
@click.option("--name", "-n", type=str, required=True)
@click.option("--mode", type=click.Choice(["fast", "safe"]), default="safe")
def cli(name, mode):
    if click.confirm(f"proceed {name}?"):
        click.echo(f"{mode}:{click.format_filename(name)}")


r = CliRunner().invoke(cli, ["--name", "x y.txt", "--mode", "fast"], input="y\n")
if r.exit_code != 0:
    print(f"confirm run exited {r.exit_code}: {r.output}", file=sys.stderr)
    sys.exit(1)
if not r.output.strip().endswith("fast:x y.txt"):
    print(f"confirm output = {r.output!r}", file=sys.stderr)
    sys.exit(1)

# an invalid choice has to be rejected by the type machinery
r2 = CliRunner().invoke(cli, ["--name", "z", "--mode", "turbo"])
if r2.exit_code == 0:
    print("Choice accepted 'turbo'", file=sys.stderr)
    sys.exit(1)
print("c3 ok: interactive confirm, Choice coercion, filename formatting")