"""Hidden case for outrigger-ferry: three string-valued build config
settings (one containing a space) plus a three-item list, asserting each
string is rendered as exactly one whole-value flag.

The VALUES are generated RANDOMLY at run time (letters, digits, spaces,
dashes, dots, underscores, equals) so no fixed input can be enumerated
or hardcoded: the graded property is that ANY plain-string value renders
as one whole flag, which is exactly the upstream bug's contract.

Fails on the parent-era code: every string value is split per character,
so no whole-value flag for a multi-character string is ever present.
Passes once the fix wraps string values in a list before iterating.
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


def test_outrigger_hidden_multi_string(
    mocker, config, pool, io, env, fixture_dir
) -> None:
    first = _rand_value(5, 12)
    second = _rand_value(5, 12)
    # put a space in the second value on purpose by appending two chunks
    second = second + " " + _rand_value(2, 4)
    items = [_rand_value(3, 8) for _ in range(3)]
    settings = {
        "CC": first,
        "LDFLAGS": second,
        "--build-option": items,
    }

    error = BuildBackendException(Exception("build failed"), description="build failed")
    mocker.patch.object(ProjectBuilder, "build", side_effect=error)
    io.set_verbosity(Verbosity.NORMAL)

    config.merge({"installer": {"build-config-settings": {"simple-project": settings}}})

    executor = Executor(env, pool, config, io)
    source_url = fixture_dir("simple_project").resolve().as_posix()
    package = Package(
        "simple-project", "1.2.3", source_type="directory", source_url=source_url
    )

    executor.execute([Install(package)])

    output = io.fetch_output()
    # every plain-string value renders as exactly ONE whole-value flag
    flag_cc = f"--config-settings='CC={first}'"
    flag_ld = f"--config-settings='LDFLAGS={second}'"
    assert flag_cc in output, output
    assert flag_ld in output, output
    assert output.count(flag_cc) == 1, output
    assert output.count(flag_ld) == 1, output
    # array values keep one flag per item
    for item in items:
        assert f"--config-settings='--build-option={item}'" in output, output
    # per-character fragments of the string values are gone
    assert f"--config-settings='CC={first[0]}'" not in output, output
    assert f"--config-settings='LDFLAGS={second[0]}'" not in output, output