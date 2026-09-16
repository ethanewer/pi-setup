import sys
import click
from click.testing import CliRunner

# Hidden case 1: bare Command that declares an argument, invoked with no args.
# The upstream golden Command test uses no declared parameters; this exercises
# the same no-args-help path from a Command that DOES declare parameters.
cmd = click.Command("t", no_args_is_help=True, params=[click.Argument(["x"])])

r = CliRunner().invoke(cmd, [])
if r.exit_code != 2:
    print(f"h1: exit {r.exit_code} != 2", file=sys.stderr)
    sys.exit(1)
if "Show this message and exit." not in r.output:
    print(f"h1: help text missing from output {r.output!r}", file=sys.stderr)
    sys.exit(1)

# The help shown in this situation must arrive as a usage error (exit code 2),
# not as a plain Exit, when the library is used outside standalone mode.
# (CliRunner.invoke swallows Exit, so drive Command.main directly - this is
# what a library embedder sees.)
try:
    cmd.main([], standalone_mode=False)
    print("h1: no exception from parse of a no-args help invocation", file=sys.stderr)
    sys.exit(1)
except click.UsageError as e:
    if e.exit_code != 2:
        print(f"h1: UsageError exit_code {e.exit_code} != 2", file=sys.stderr)
        sys.exit(1)
    if "Show this message and exit." not in str(e):
        print(f"h1: UsageError message is not the help text: {str(e)!r}", file=sys.stderr)
        sys.exit(1)
except click.exceptions.Exit:
    print("h1: plain Exit raised instead of a UsageError (pre-fix behaviour)", file=sys.stderr)
    sys.exit(1)
print("h1 ok")