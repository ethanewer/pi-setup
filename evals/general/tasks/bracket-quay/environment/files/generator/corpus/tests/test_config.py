"""Config loading and validation tests."""

import pytest

from quaydoc.config import SiteConfig, load_config
from quaydoc.errors import ConfigError


def test_defaults(tmp_path):
    cfg = load_config(str(tmp_path))
    assert cfg.title == "Docs"
    assert cfg.pretty_urls is True
    assert cfg.output_dir == "site"


def test_load_toml(tmp_path):
    (tmp_path / "quaydoc.toml").write_text(
        "[site]\ntitle = \"Manual\"\nbase_url = \"https://x.test/\"\n"
        "pretty_urls = false\n\n[build]\noutput_dir = \"out\"\n"
        "rss = false\n", encoding="utf-8")
    cfg = load_config(str(tmp_path))
    assert cfg.title == "Manual"
    assert cfg.pretty_urls is False
    assert cfg.output_dir == "out"
    assert cfg.rss is False


def test_unknown_keys_are_warnings(tmp_path):
    (tmp_path / "quaydoc.toml").write_text(
        "[site]\ntitle = \"X\"\nbogus_key = true\n", encoding="utf-8")
    cfg = load_config(str(tmp_path))
    assert any("bogus_key" in w for w in cfg.warnings)


def test_unknown_top_level_raises(tmp_path):
    (tmp_path / "quaydoc.toml").write_text(
        "[nope]\nx = 1\n", encoding="utf-8")
    with pytest.raises(ConfigError):
        load_config(str(tmp_path))


def test_invalid_toml_raises(tmp_path):
    (tmp_path / "quaydoc.toml").write_text("not [valid\n", encoding="utf-8")
    with pytest.raises(ConfigError):
        load_config(str(tmp_path))


def test_env_interpolation(tmp_path, monkeypatch):
    monkeypatch.setenv("QUAYDOC_TITLE", "FromEnv")
    (tmp_path / "quaydoc.toml").write_text(
        "[site]\ntitle = \"${QUAYDOC_TITLE}\"\n", encoding="utf-8")
    cfg = load_config(str(tmp_path))
    assert cfg.title == "FromEnv"


def test_env_fallback(tmp_path):
    (tmp_path / "quaydoc.toml").write_text(
        "[site]\ntitle = \"${NOPE:-Fallback}\"\n", encoding="utf-8")
    cfg = load_config(str(tmp_path))
    assert cfg.title == "Fallback"


def test_output_path_absolutes(tmp_path):
    cfg = load_config(str(tmp_path))
    assert cfg.output_path == str(tmp_path / "site")
