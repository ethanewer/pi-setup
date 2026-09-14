"""Hidden case: os.stat of the home directory raises PermissionError.

The upstream regression test only covers a home directory that does not
exist (FileNotFoundError). A repair that catches only FileNotFoundError
still crashes when the home directory cannot be stat'ed for another reason
(for example a permission-denied path). A correct repair must treat any
OSError from the home stat the way it treats an unset home.
"""
import os
from unittest import mock

from flake8.options import config


def _guarded_stat(home):
    real_stat = os.stat

    def guarded(path):
        if os.fspath(path) == home:
            raise PermissionError(13, "Permission denied", path)
        return real_stat(path)

    return guarded


def test_home_stat_permission_error_is_ignored(tmp_path):
    home = "/nowhere-owner/home-dir"
    with mock.patch.object(os.path, "expanduser", return_value=home), \
         mock.patch.object(config.os, "stat", side_effect=_guarded_stat(home)):
        assert config._find_config_file(str(tmp_path)) is None


def test_load_config_survives_home_stat_permission_error(tmp_path):
    home = "/nowhere-owner/home-dir"
    old_cwd = os.getcwd()
    os.chdir(tmp_path)
    try:
        with mock.patch.object(os.path, "expanduser", return_value=home), \
             mock.patch.object(config.os, "stat", side_effect=_guarded_stat(home)):
            cfg, cfg_dir = config.load_config(None, [], isolated=False)
    finally:
        os.chdir(old_cwd)
    assert cfg.sections() == []
    assert cfg_dir == os.path.abspath(str(tmp_path))