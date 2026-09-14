"""Hidden case: same code path as the upstream regression, different input.

Like the upstream regression test the home directory does not exist, but
here the missing home is a deep multi-component path under a non-existent
root, and the starting directory is a synthetic project two levels below a
real temporary root. Discovery must traverse upwards across the missing
home without ever stat'ing it and terminate normally with "no config".
"""
import os
from unittest import mock

from flake8.options import config


def test_deep_nonexistent_home_is_ignored(tmp_path):
    project = tmp_path.joinpath("tree", "project")
    project.mkdir(parents=True)

    with mock.patch.object(
        os.path, "expanduser", return_value="/nonexistent/deep/path/home"
    ):
        assert config._find_config_file(str(project)) is None


def test_deep_nonexistent_home_with_config_above_first_level(tmp_path):
    project = tmp_path.joinpath("half", "project")
    project.mkdir(parents=True)
    tmp_path.joinpath("setup.cfg").write_text("[flake8]\n")

    with mock.patch.object(
        os.path, "expanduser", return_value="/nonexistent/deep/path/home"
    ):
        assert config._find_config_file(str(project)) == str(
            tmp_path.joinpath("setup.cfg")
        )