"""Hidden case for outrigger-ferry: plain-string settings whose values are
punctuation- and digit-heavy (spaces, dashes, dots, equals signs,
uppercase and lowercase letters). On the parent-era code the per-character
iteration splits these into fragments; a correct fix emits each value
intact in one flag.

The VALUES are generated RANDOMLY at run time (letters, digits, spaces,
dashes, dots, underscores, equals) so no fixed input can be enumerated
or hardcoded; the graded property is the general whole-value contract.
Also covers an array setting with a single item, verifying the array path
stays one-flag-per-item once strings are wrapped.
"""
from __future__ import annotations

import random
import string

from build import BuildBackendException
from build import ProjectBuilder

from cleo.io.outputs.output import Verbosity

from poetry.installation.executor import Executor
from poetry.installation.operations import Install
from poetry.core.packages.package import Package

import pytest
from cleo.formatters.style import Style
from cleo.io.buffered_io import BufferedIO


@pytest.fixture
def io() -> BufferedIO:
    io = BufferedIO()
    io.output.formatter.set_style("c1_dark", Style("cyan", options=["dark"]))
    io.output.formatter.set_style("c2_dark", Style("default", options=["bold", "dark"]))
    return io


ALPHABET = string.ascii_letters + string.digits + " _-.="


def _rand_value(min_len: int = 3, max_len: int = 24) -> str:
    """Random value with at least two distinct characters so per-character
    iteration on the parent-era code visibly splits it. Ensure digit and
    punctuation characters are present so the value is not a bare word."""
    while True:
        n = random.randint(min_len, max_len)
        v = "".join(random.choice(ALPHABET) for _ in range(n))
        if len(set(v)) >= 2 and any(ch in ".-=_" for ch in v):
            return v


def test_outrigger_hidden_punctuation_string(
    mocker, config, pool, io, env, fixture_dir
) -> None:
    first = _rand_value(8, 20)
    second = _rand_value(8, 20) + " " + _rand_value(3, 6)
    single = _rand_value(3, 8)

    error = BuildBackendException(Exception("build failed"), description="build failed")
    mocker.patch.object(ProjectBuilder, "build", side_effect=error)
    io.set_verbosity(Verbosity.NORMAL)

    config.merge(
        {
            "installer": {
                "build-config-settings": {
                    "simple-project": {
                        "BUILD-TAG": first,
                        "WHEEL-ARGS": second,
                        "FLAGLIST": [single],
                    },
                },
            },
        }
    )

    executor = Executor(env, pool, config, io)
    source_url = fixture_dir("simple_project").resolve().as_posix()
    package = Package(
        "simple-project", "1.2.3", source_type="directory", source_url=source_url
    )

    executor.execute([Install(package)])

    output = io.fetch_output()
    flag1 = f"--config-settings='BUILD-TAG={first}'"
    flag2 = f"--config-settings='WHEEL-ARGS={second}'"
    flag3 = f"--config-settings='FLAGLIST={single}'"
    assert flag1 in output, output
    assert output.count(flag1) == 1, output
    assert flag2 in output, output
    assert output.count(flag2) == 1, output
    assert flag3 in output, output
    # per-character fragments of the long string values must be gone
    assert f"--config-settings='BUILD-TAG={first[0]}'" not in output, output
    assert f"--config-settings='WHEEL-ARGS={second[0]}'" not in output, output