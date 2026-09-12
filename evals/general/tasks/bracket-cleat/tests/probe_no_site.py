#!/usr/bin/env python3
"""site-free behaviour probe for bracket-cleat (verifier fixture).

Runs under `python3 -S` with PYTHONPATH pointing at /app/src/src, so neither
sitecustomize.py nor any .pth shim can influence the result: either the
checked-out click source behaves like a fixed valueless flag, or this exits
non-zero. Shipped under /tests and re-uploaded pristine at verify time.
"""
import sys

sys.path = [p for p in sys.path if p]
import click  # noqa: E402  (resolved from PYTHONPATH=/app/src/src)
from click.testing import CliRunner  # noqa: E402


@click.command()
@click.option("--name", is_flag=False, flag_value="Flag", default="Default")
def hello(name: str) -> None:
    click.echo(f"Hello, {name}!")


def main() -> int:
    r = CliRunner().invoke(hello, ["--name"])
    ok = r.exit_code == 0 and r.output == "Hello, Flag!\n"
    print("exit:", r.exit_code, "| output:", repr(r.output))
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())