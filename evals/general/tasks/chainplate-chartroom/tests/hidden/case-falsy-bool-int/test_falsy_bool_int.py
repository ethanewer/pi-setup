"""Hidden case: falsy booleans and integer zero in template resolution.

The upstream regression test (test_config_process_resolves_falsy_values)
only exercises the integer zero that ships in the default config
(requests.max-retries). These tests drive the same code path from falsy
values the upstream test does not use, and through different input routes:
False booleans set via the configuration dictionary, an integer zero set via
the configuration dictionary, an integer zero arriving through the
POETRY_* environment route, and a falsy value inside a larger surrounding
template.

At the parent commit every one of these asserts fails: the referenced falsy
value is treated as unset and the literal "{...}" template is returned.
With the fix, the placeholder is replaced by the value's string form.
"""
from __future__ import annotations

import sys

sys.path.insert(0, "/app/src/src")

import pytest

from poetry.config.config import Config
from poetry.config.dict_config_source import DictConfigSource


def make_config(overrides: dict, use_environment: bool = False) -> Config:
    c = Config(use_environment=use_environment)
    src = DictConfigSource()
    for key, value in overrides.items():
        src.add_property(key, value)
    c.merge(src.config)
    c.set_config_source(src)
    return c


def test_boolean_false_values_resolve() -> None:
    c = make_config(
        {"installer.parallel": False, "virtualenvs.options.always-copy": False}
    )
    assert c.process("{installer.parallel}") == "False"
    assert c.process("{virtualenvs.options.always-copy}") == "False"


def test_integer_zero_from_config_dict_resolves() -> None:
    c = make_config({"installer.max-workers": 0})
    assert c.process("{installer.max-workers}") == "0"


def test_integer_zero_from_environment_route_resolves(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("POETRY_INSTALLER_MAX_WORKERS", "0")
    c = make_config({}, use_environment=True)
    assert c.process("{installer.max-workers}") == "0"


def test_falsy_value_in_surrounding_text() -> None:
    c = make_config({"installer.max-workers": 0})
    assert c.process("retrying at most {installer.max-workers} times") == (
        "retrying at most 0 times"
    )