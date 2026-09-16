"""Hidden case for bracket-cleat: the valueless-flag code path driven through
short options, attached values and option-looking neighbours.

The upstream regression test only passes the long option ``--name`` by
itself. This case exercises the same code path from inputs it does not use:
the short form ``-n``, attached explicit values (``-nCarol`` /
``--name=Alice``), and the guarantee that a bare valueless flag never
swallows a following option.
"""
import click
from click.testing import CliRunner


def make_cli():
    @click.command()
    @click.option(
        "-n", "--name", is_flag=False, flag_value="Flag", default="Default"
    )
    @click.option("--other", is_flag=True)
    @click.argument("item", required=False)
    def cli(name, other, item):
        click.echo(f"name={name!r} other={other!r} item={item!r}")

    return cli


def test_bare_short_option_uses_flag_value():
    r = CliRunner().invoke(make_cli(), ["-n"])
    assert r.exit_code == 0, r.output
    assert r.output == "name='Flag' other=False item=None\n"


def test_bare_long_option_does_not_swallow_following_option():
    r = CliRunner().invoke(make_cli(), ["--name", "--other"])
    assert r.exit_code == 0, r.output
    assert r.output == "name='Flag' other=True item=None\n"


def test_attached_and_space_explicit_values_still_accepted():
    cli = make_cli()
    r1 = CliRunner().invoke(cli, ["--name", "Bob"])
    assert r1.exit_code == 0, r1.output
    assert r1.output == "name='Bob' other=False item=None\n"
    r2 = CliRunner().invoke(cli, ["--name=Alice"])
    assert r2.exit_code == 0, r2.output
    assert r2.output == "name='Alice' other=False item=None\n"
    r3 = CliRunner().invoke(cli, ["-nCarol"])
    assert r3.exit_code == 0, r3.output
    assert r3.output == "name='Carol' other=False item=None\n"


def test_missing_option_uses_default():
    r = CliRunner().invoke(make_cli(), [])
    assert r.exit_code == 0, r.output
    assert r.output == "name='Default' other=False item=None\n"