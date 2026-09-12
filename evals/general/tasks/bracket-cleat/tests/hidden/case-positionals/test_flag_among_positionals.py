"""Hidden case for bracket-cleat: a valueless flag appearing among positional
arguments and other options, where the flag ``--verb`` carries a flag_value
and a default.

The upstream regression test invokes the flagged command with the option
alone. This case proves the same fixed behaviour survives when the option is
interleaved with arguments in a realistic command line.
"""
import click
from click.testing import CliRunner


def make_speak():
    @click.command()
    @click.option("--verb", is_flag=False, flag_value="loud", default="quiet")
    @click.option("--times", type=int, default=1)
    @click.argument("words", nargs=-1)
    def speak(verb, times, words):
        for _ in range(times):
            click.echo(f"{verb}: {' '.join(words)}")

    return speak


def test_bare_flag_does_not_swallow_following_option():
    r = CliRunner().invoke(make_speak(), ["hey", "--verb", "--times", "2"])
    assert r.exit_code == 0, r.output
    assert r.output == "loud: hey\nloud: hey\n"


def test_explicit_value_still_consumed_after_option():
    r = CliRunner().invoke(make_speak(), ["hello", "--verb", "shout", "--times", "1"])
    assert r.exit_code == 0, r.output
    assert r.output == "shout: hello\n"


def test_default_used_when_flag_absent():
    r = CliRunner().invoke(make_speak(), ["hi", "--times", "1"])
    assert r.exit_code == 0, r.output
    assert r.output == "quiet: hi\n"