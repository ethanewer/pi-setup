import click
from click.testing import CliRunner

def test_command_no_args_is_help():
    result = CliRunner().invoke(click.Command("t", no_args_is_help=True), [])
    assert result.exit_code == 2, f"command: expected exit 2, got {result.exit_code}"
    assert "Show this message and exit." in result.output

def test_group_no_args_is_help():
    @click.group()
    def cli():
        pass
    result = CliRunner().invoke(cli, [])
    assert result.exit_code == 2, f"group: expected exit 2, got {result.exit_code}"
    assert "Show this message and exit." in result.output
