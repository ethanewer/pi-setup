"""Hidden case for bracket-compass: statement kinds the upstream regression
test does not use.

The upstream regression test covers empty/blank required blocks (accepted) and
text, a nested child block and an if-statement (rejected).  These cases drive
the same code path from inputs it does not use: a for-loop, a set statement, a
comment followed by a statement, and a {{ expression }} output node.  Each
must produce the intended TemplateSyntaxError -- never an AttributeError -- and
required blocks that are empty or whitespace/comment-only must keep compiling.
"""

import pytest

from jinja2 import Environment
from jinja2 import TemplateSyntaxError

MESSAGE = "Required blocks can only contain comments or whitespace"


def _compile(src: str):
    return Environment().from_string(src)


def test_required_block_with_for_loop_raises_cleanly() -> None:
    src = (
        "{% block x required %}"
        "{% for i in [1, 2, 3] %}{{ i }}{% endfor %}"
        "{% endblock %}"
    )
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        _compile(src)


def test_required_block_with_set_statement_raises_cleanly() -> None:
    src = "{% block x required %}{% set y = 1 %}{% endblock %}"
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        _compile(src)


def test_required_block_with_comment_and_statement_raises_cleanly() -> None:
    src = (
        "{% block x required %}{# doc #}"
        "{% if data %}{% endif %}{% endblock %}"
    )
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        _compile(src)


def test_required_block_with_expression_output_raises_cleanly() -> None:
    # {{ value }} parses to an Output node whose child is not TemplateData,
    # so it must be rejected even though it would render as text.
    src = "{% block x required %}{{ value }}{% endblock %}"
    with pytest.raises(TemplateSyntaxError, match=MESSAGE):
        _compile(src)


def test_empty_and_comment_only_required_blocks_still_compile() -> None:
    env = Environment()
    for src in (
        "{% block x required %}{% endblock %}",
        "{% block x required %}{% endblock %} ",
        "{% block x required %}{# only a comment #}{% endblock %}",
        "{% block x required %}{# c #}  {# more #}{% endblock %}",
    ):
        env.from_string(src)  # must parse/compile without raising