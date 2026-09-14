"""Hidden case for outrigger-ferry: an EMPTY plain-string build config
setting next to two random string settings and a two-item list. On the
parent-era code an empty string iterates zero times, so the setting
vanishes from the remediation pip command entirely; a correct fix renders
it as a single '--config-settings='MYVAR='' flag.

The VALUES are generated RANDOMLY at run time (letters, digits, spaces,
dashes, dots, underscores, equals) so no fixed input can be enumerated
or hardcoded; the graded property is the empty-string rendering plus the
general whole-value contract.
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
    iteration on the parent-era code visibly splits it."""
    while True:
        n = random.randint(min_len, max_len)
        v = "".join(random.choice(ALPHABET) for _ in range(n))
        if len(set(v)) >= 2:
            return v


def test_outrigger_hidden_empty_string(
    mocker, config, pool, io, env, fixture_dir
) -> None:
    second = _rand_value(5, 12)
    items = [_rand_value(3, 8) for _ in range(2)]

    error = BuildBackendException(Exception("build failed"), description="build failed")
    mocker.patch.object(ProjectBuilder, "build", side_effect=error)
    io.set_verbosity(Verbosity.NORMAL)

    config.merge(
        {
            "installer": {
                "build-config-settings": {
                    "simple-project": {
                        "MYVAR": "",
                        "CC": second,
                        "--build-option": items,
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
    # the empty-string setting must still appear, once, as a single flag
    flag_empty = "--config-settings='MYVAR='"
    flag_cc = f"--config-settings='CC={second}'"
    assert flag_empty in output, output
    assert output.count(flag_empty) == 1, output
    assert flag_cc in output, output
    assert output.count(flag_cc) == 1, output
    for item in items:
        assert f"--config-settings='--build-option={item}'" in output, output
    # per-character fragments of the non-empty string value are gone
    assert f"--config-settings='CC={second[0]}'" not in output, output