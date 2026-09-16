"""Hidden case: the ValueError message must reach the user at the CLI level.

A full CliRunner invocation of a command whose option type is a
FuncParamType that raises ValueError with its own message.  The user must see
the ValueError message; the raw input value must NOT be echoed back.
"""

import click
import click.testing
import pytest


def _parse_port(value):
    if not (isinstance(value, str) and value.isdigit() and len(value) == 4):
        raise ValueError("must be a four-digit port number")
    return int(value)


@pytest.fixture
def cli():
    @click.command()
    @click.option(
        "--port",
        type=click.types.FuncParamType(_parse_port),
        required=True,
    )
    def cli(port):
        click.echo(f"port={port}")

    return cli


def test_value_error_message_reaches_user(cli):
    result = click.testing.CliRunner().invoke(cli, ["--port", "notaport"])

    assert result.exit_code == 2
    assert "must be a four-digit port number" in result.output
    assert "notaport" not in result.output


def test_too_short_value_also_rejected(cli):
    result = click.testing.CliRunner().invoke(cli, ["--port", "808"])

    assert result.exit_code == 2
    assert "must be a four-digit port number" in result.output


def test_valid_value_still_converts(cli):
    result = click.testing.CliRunner().invoke(cli, ["--port", "8080"])

    assert result.exit_code == 0
    assert "port=8080" in result.output