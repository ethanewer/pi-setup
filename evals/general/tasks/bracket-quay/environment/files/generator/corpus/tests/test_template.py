"""Template engine tests."""

import pytest

from quaydoc.errors import TemplateError
from quaydoc.template import Template


def render(text, context=None, loader=None):
    return Template(text).render(context or {}, loader)


def test_interpolation():
    assert render("Hello, {{ name }}!", {"name": "quaydoc"}) == \
        "Hello, quaydoc!"


def test_unknown_variable_empty():
    assert render("[{{ missing }}]") == "[]"


def test_dotted_lookup():
    assert render("{{ user.name }}", {"user": {"name": "ana"}}) == "ana"


def test_filter_lower_upper():
    assert render("{{ name|upper }}", {"name": "ana"}) == "ANA"
    assert render("{{ name|lower }}", {"name": "ANA"}) == "ana"


def test_filter_escape():
    assert render("{{ x|escape }}", {"x": "<b>"}) == "&lt;b&gt;"


def test_filter_default():
    assert render("[{{ x|default('fallback') }}]", {}) == "[fallback]"
    assert render("[{{ x|default('fallback') }}]", {"x": "kept"}) == "[kept]"


def test_filter_length_join():
    assert render("{{ items|length }}", {"items": [1, 2, 3]}) == "3"
    assert render("{{ items|join(' / ') }}", {"items": ["a", "b"]}) == "a / b"


def test_if_else():
    tmpl = "{% if ok %}yes{% else %}no{% endif %}"
    assert render(tmpl, {"ok": True}) == "yes"
    assert render(tmpl, {"ok": False}) == "no"


def test_if_elif():
    tmpl = "{% if n == 1 %}one{% elif n == 2 %}two{% else %}many{% endif %}"
    assert render(tmpl, {"n": 2}) == "two"
    assert render(tmpl, {"n": 9}) == "many"


def test_if_not():
    assert render("{% if not hidden %}shown{% endif %}") == "shown"


def test_for_loop():
    assert render("{% for x in items %}{{ x }};{% endfor %}",
                  {"items": [1, 2]}) == "1;2;"


def test_for_loop_vars():
    result = render(
        "{% for x in items %}{{ loop.index }}:{{ x }}{% if loop.last %}"
        "!{% endif %}{% endfor %}", {"items": ["a", "b"]})
    assert result == "1:a2:b!"


def test_include():
    loader = {"part": Template("({{ x }})")}
    assert render("{% include \"part\" %}", {"x": 3}, loader) == "(3)"


def test_set_tag():
    assert render("{% set x = 5 %}[{{ x }}]") == "[5]"


def test_comment():
    assert render("a{% comment %}secret{% endcomment %}b") == "ab"


def test_raw():
    # the raw body is preserved verbatim except that token spacing is
    # normalised by the scanner
    assert render("{% raw %}{{ not_rendered }}{% endraw %}") == \
        "{{not_rendered}}"


def test_unknown_tag_raises():
    with pytest.raises(TemplateError):
        Template("{% nope %}")


def test_unclosed_if_raises():
    with pytest.raises(TemplateError):
        Template("{% if x %}never closed")
