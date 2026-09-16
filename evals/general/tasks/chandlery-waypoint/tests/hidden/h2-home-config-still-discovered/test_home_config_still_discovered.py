"""Hidden case: a stat-able home directory must keep working exactly as before.

The upstream regression test only covers a non-existent home. These tests
guard the other half of the repair: when the home directory exists, config
discovery from the home directory must still behave identically to the
pre-bug behaviour -- a config in the home is found when discovery starts
there, and the walk upwards still stops at the home boundary.
"""
import os
from unittest import mock

from flake8.options import config


def test_home_config_still_found_when_starting_in_home(tmp_path):
    home = str(tmp_path)
    tmp_path.joinpath(".flake8").write_text("[flake8]\nmax-line-length=111\n")

    with mock.patch.object(os.path, "expanduser", return_value=home):
        assert config._find_config_file(home) == os.path.join(home, ".flake8")


def test_walk_still_stops_at_existing_home(tmp_path):
    home = str(tmp_path)
    sub = tmp_path.joinpath("d")
    sub.mkdir()
    tmp_path.joinpath("setup.cfg").write_text("[flake8]\n")

    with mock.patch.object(os.path, "expanduser", return_value=home):
        assert config._find_config_file(str(sub)) is None