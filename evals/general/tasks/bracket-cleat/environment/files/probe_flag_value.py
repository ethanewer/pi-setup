#!/usr/bin/env python3
"""Probe for bracket-cleat: invokes a valueless-flag option with no value.

Declares the exact mixed declaration from the bug (is_flag=False together
with flag_value and default), invokes the command with only the option name,
and prints the CLI exit code and captured output. Exits non-zero while the
bug is present (click refuses the argument and exits 2) and zero once the
option behaves like a valueless flag and uses its flag_value.
"""
import click
from click.testing import CliRunner


@click.command()
@click.option("--name", is_flag=False, flag_value="Flag", default="Default")
def hello(name: str) -> None:
    click.echo(f"Hello, {name}!")


if __name__ == "__main__":
    result = CliRunner().invoke(hello, ["--name"])
    print("exit:", result.exit_code, "| output:", repr(result.output))
    expected_ok = result.exit_code == 0 and result.output == "Hello, Flag!\n"
    raise SystemExit(0 if expected_ok else 1)