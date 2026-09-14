import sys
import click
from click.core import Context


def direct(cmd):
    """Drive parse_args directly, bypassing CliRunner entirely."""
    try:
        cmd.parse_args(Context(cmd), [])
    except click.UsageError as e:
        return e
    except BaseException as e:  # noqa: B036 - any other exception is a failure
        print(f"h3: unexpected exception {type(e).__name__}: {e}", file=sys.stderr)
        return None
    return None


# Hidden case 3: the real API path, no CliRunner. A bare group configured with
# no_args_is_help must surface the help as a usage error with exit code 2 from
# the library's own parse step, not as a successful help print.
g = click.Group(no_args_is_help=True)
e = direct(g)
if not isinstance(e, click.UsageError):
    print("h3: Group.parse_args did not raise a UsageError for a bare group", file=sys.stderr)
    sys.exit(1)
if e.exit_code != 2:
    print(f"h3: UsageError exit_code {e.exit_code} != 2", file=sys.stderr)
    sys.exit(1)
if "Show this message and exit." not in str(e):
    print(f"h3: usage-error message is not the help text: {str(e)!r}", file=sys.stderr)
    sys.exit(1)

c = click.Command("t", no_args_is_help=True)
e2 = direct(c)
if not isinstance(e2, click.UsageError):
    print("h3: Command.parse_args did not raise a UsageError for a bare command", file=sys.stderr)
    sys.exit(1)
if e2.exit_code != 2:
    print(f"h3: Command UsageError exit_code {e2.exit_code} != 2", file=sys.stderr)
    sys.exit(1)

print("h3 ok")