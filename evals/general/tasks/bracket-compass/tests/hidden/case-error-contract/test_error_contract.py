"""Hidden case for bracket-compass: the exact error contract.

The friendly message must surface with its exact text, raised as a
TemplateSyntaxError at compile/parse time (both via Environment.from_string and
through a loader), while legitimate required blocks and ordinary non-required
blocks keep their current behaviour.
"""

import pytest

from jinja2 import DictLoader
from jinja2 import Environment
from jinja2 import TemplateSyntaxError

MESSAGE = "Required blocks can only contain comments or whitespace"


def test_exact_message_and_error_class() -> None:
    src = "{% block x required %}{% if true %}{% endif %}{% endblock %}"
    with pytest.raises(TemplateSyntaxError) as ei:
        Environment().from_string(src)
    assert str(ei.value) == MESSAGE


def test_error_surfaces_through_a_loader() -> None:
    env = Environment(
        loader=DictLoader(
            {
                "bad": "{% block x required %}{% for i in [1, 2] %}"
                "{% endfor %}{% endblock %}",
                "good": "{% block x required %}{% endblock %}",
            }
        )
    )
    env.get_template("good")  # must not raise
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        env.get_template("bad")


def test_non_required_blocks_containing_statements_still_compile() -> None:
    # The fix must not over-tighten: only *required* blocks are restricted.
    env = Environment()
    src = (
        "{% block x %}{% if true %}a{% else %}b{% endif %}"
        "{% for i in [1, 2] %}{{ i }}{% endfor %}"
        "{% set v = 1 %}{{ v }}{% endblock %}"
    )
    assert env.from_string(src).render() == "a121"


def test_plain_text_in_required_block_still_raises_intended_error() -> None:
    # Literal text inside a required block already produced the intended
    # error before the fix; it must keep doing so.
    src = "{% block x required %}data{% endblock %}"
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        Environment().from_string(src)