import sys
import click
from click.testing import CliRunner

# Hidden case 2: a group with subcommands and an option, invoked bare. The
# upstream golden group test declares an argument; this one declares an option
# and subcommands, hitting the same Group.parse_args no-args branch.
@click.group()
@click.option("--verbose", is_flag=True)
def cli(verbose):
    pass


@cli.command()
def go():
    click.echo("go")


r = CliRunner().invoke(cli, [])
if r.exit_code != 2:
    print(f"h2: exit {r.exit_code} != 2", file=sys.stderr)
    sys.exit(1)
if "Show this message and exit." not in r.output:
    print(f"h2: help text missing from output {r.output!r}", file=sys.stderr)
    sys.exit(1)

try:
    cli.main([], standalone_mode=False)
    print("h2: no exception from parse of a bare group invocation", file=sys.stderr)
    sys.exit(1)
except click.UsageError as e:
    if e.exit_code != 2:
        print(f"h2: UsageError exit_code {e.exit_code} != 2", file=sys.stderr)
        sys.exit(1)
    if "Show this message and exit." not in str(e):
        print(f"h2: UsageError message is not the help text: {str(e)!r}", file=sys.stderr)
        sys.exit(1)
except click.exceptions.Exit:
    print("h2: plain Exit raised instead of a UsageError (pre-fix behaviour)", file=sys.stderr)
    sys.exit(1)
print("h2 ok")