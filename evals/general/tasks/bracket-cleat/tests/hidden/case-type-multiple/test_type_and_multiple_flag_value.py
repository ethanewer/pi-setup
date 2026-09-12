"""Hidden case for bracket-cleat: type-converted flag_value and a
``multiple=True`` option mixing bare and explicit values.

The upstream regression test only exercises a plain string flag_value given
alone. This case drives the same resolution code (an option declared
``is_flag=False`` with ``flag_value`` and ``default``) through a typed flag
and through a repeatable option.
"""
import click
from click.testing import CliRunner


def test_flag_value_is_type_converted_when_used_valueless():
    @click.command()
    @click.option("--count", is_flag=False, flag_value="2", default=1, type=int)
    def repeat(count):
        click.echo(f"count={count!r} ({type(count).__name__})")

    runner = CliRunner()
    r1 = runner.invoke(repeat, ["--count"])
    assert r1.exit_code == 0, r1.output
    assert r1.output == "count=2 (int)\n"
    r2 = runner.invoke(repeat, ["--count", "5"])
    assert r2.exit_code == 0, r2.output
    assert r2.output == "count=5 (int)\n"
    r4 = runner.invoke(repeat, [])
    assert r4.exit_code == 0, r4.output
    assert r4.output == "count=1 (int)\n"


def test_multiple_mixes_bare_and_explicit_values():
    cli = click.Command(
        "cli",
        params=[
            click.Option(
                ["-m", "--mode"],
                is_flag=False,
                flag_value="fast",
                default=("slow",),
                multiple=True,
            ),
            click.Option(["-a"]),
            click.Argument(["b"], nargs=-1),
        ],
        callback=lambda **kwargs: kwargs,
    )
    runner = CliRunner()
    r = runner.invoke(
        cli,
        ["--mode", "--mode", "quick", "-m", "-a", "1", "x", "y"],
        standalone_mode=False,
        catch_exceptions=False,
    )
    assert r.exit_code == 0, r.output
    assert r.return_value == {
        "mode": ("fast", "quick", "fast"),
        "a": "1",
        "b": ("x", "y"),
    }