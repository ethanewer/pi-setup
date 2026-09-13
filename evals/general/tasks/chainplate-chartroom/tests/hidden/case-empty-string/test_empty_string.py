"""Hidden case: empty-string falsy values in template resolution.

The upstream regression test uses max-retries=0; this case covers the other
falsy family member the issue describes: an empty-string configured value,
which `if config_value:` also treats as unset. Each test drives the same
Config.process() interpolation path from an empty-string value, including
one embedded between literal text. At the parent commit the literal
"{key}" template is returned; with the fix the placeholder collapses to the
empty string.
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/app/src/src")

from poetry.config.config import Config
from poetry.config.dict_config_source import DictConfigSource


def make_config(overrides: dict) -> Config:
    c = Config(use_environment=False)
    src = DictConfigSource()
    for key, value in overrides.items():
        src.add_property(key, value)
    c.merge(src.config)
    c.set_config_source(src)
    return c


def test_empty_string_installer_no_binary_resolves() -> None:
    c = make_config({"installer.no-binary": ""})
    assert c.process("{installer.no-binary}") == ""


def test_empty_string_cache_dir_resolves() -> None:
    c = make_config({"cache-dir": ""})
    assert c.process("{cache-dir}") == ""


def test_empty_string_inside_larger_template() -> None:
    c = make_config({"installer.no-binary": ""})
    assert c.process("pkg:{installer.no-binary}:end") == "pkg::end"