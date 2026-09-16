"""Hidden case for bracket-compass: required blocks inside an inheritance
hierarchy, driven through a real FileSystemLoader with files on disk.

Required blocks can sit in either the parent or the child template of an
extends chain.  Statement content must be rejected cleanly in both positions;
a child that overrides a required block with real content stays valid.
"""

import pytest

from jinja2 import Environment
from jinja2 import FileSystemLoader
from jinja2 import TemplateSyntaxError

MESSAGE = "Required blocks can only contain comments or whitespace"


def _env(template_dir) -> Environment:
    return Environment(loader=FileSystemLoader(str(template_dir)))


def test_required_block_with_statement_in_child_template(tmp_path) -> None:
    (tmp_path / "base.html").write_text(
        "{% block body required %}{% endblock %}"
    )
    # valid: the child overrides the required block with real content
    (tmp_path / "child.html").write_text(
        "{% extends 'base.html' %}{% block body %}"
        "{% set v = 1 %}{{ v }}{% endblock %}"
    )
    env = _env(tmp_path)
    env.get_template("base.html")  # the required block itself compiles fine
    assert env.get_template("child.html").render() == "1"

    # invalid: a *required* block in the child containing a nested block
    (tmp_path / "bad.html").write_text(
        "{% extends 'base.html' %}{% block body required %}"
        "{% block inner %}{% endblock %}{% endblock %}"
    )
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        env.get_template("bad.html")


def test_required_block_with_statement_in_parent_template(tmp_path) -> None:
    # A required block cannot hide an if-statement in a child either: the
    # parent declares the required block body, so the check fires when the
    # parent template is compiled.
    (tmp_path / "layout.html").write_text(
        "{% block head required %}{% if true %}{% endif %}{% endblock %}"
    )
    (tmp_path / "page.html").write_text(
        "{% extends 'layout.html' %}{% block head %}real{% endblock %}"
    )
    env = _env(tmp_path)
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        env.get_template("layout.html")
    # page extends layout; the parent is only parsed when the page renders,
    # and the same error must surface there.
    page = env.get_template("page.html")
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        page.render()


def test_required_block_empty_via_loader_still_compiles(tmp_path) -> None:
    (tmp_path / "ok.html").write_text(
        "{% block x required %}{# nothing but a comment #}{% endblock %}"
    )
    (tmp_path / "child_ok.html").write_text(
        "{% extends 'ok.html' %}{% block x %}{% endblock %}"
    )
    env = _env(tmp_path)
    env.get_template("ok.html")  # the required block alone parses fine
    # a child that satisfies the required block renders through it
    assert env.get_template("child_ok.html").render() == ""