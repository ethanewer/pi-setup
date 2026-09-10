"""Lexer unit tests."""

import pytest

from quaydoc import lexer
from quaydoc.errors import ParseError
from quaydoc.tokens import TokenKind


def lex(text):
    tokens = lexer.lex(text)
    if tokens and tokens[-1].kind is TokenKind.BLANK:
        tokens = tokens[:-1]
    return tokens


def kinds(text):
    return [(t.kind, t.text) for t in lex(text)]


def test_headings_have_levels():
    tokens = lex("# One\n## Two\n###### Six\n")
    assert [(t.kind, t.level, t.text) for t in tokens] == [
        (TokenKind.HEADING, 1, "One"),
        (TokenKind.HEADING, 2, "Two"),
        (TokenKind.HEADING, 6, "Six"),
    ]


def test_paragraph_lines_are_text():
    assert kinds("hello world\nsecond line\n") == [
        (TokenKind.TEXT, "hello world"), (TokenKind.TEXT, "second line")]


@pytest.mark.parametrize("line,ordered", [
    ("- item", False), ("* star", False), ("1. first", True),
    ("17. seventeen", True), ("  - nested", False),
])
def test_list_items(line, ordered):
    tokens = lex(line + "\n")
    assert tokens[0].kind is TokenKind.LIST_ITEM
    assert tokens[0].meta["ordered"] is ordered


def test_list_indent_levels():
    tokens = lex("- a\n  - b\n    - c\n")
    assert [t.level for t in tokens] == [0, 1, 2]


def test_quote_marker_removed():
    assert kinds("> quoted line\n") == [(TokenKind.QUOTE, "quoted line")]


def test_fenced_code_block():
    tokens = lex("```python\nprint(1)\n```\n")
    assert [t.kind for t in tokens] == [
        TokenKind.CODE_FENCE_OPEN, TokenKind.CODE_LINE,
        TokenKind.CODE_FENCE_CLOSE]
    assert tokens[0].meta["lang"] == "python"


def test_fence_preserves_interior_blanks():
    tokens = lex("```\na\n\nb\n```\n")
    assert [(t.kind, t.text) for t in tokens[1:-1]] == [
        (TokenKind.CODE_LINE, "a"), (TokenKind.CODE_LINE, ""),
        (TokenKind.CODE_LINE, "b")]


def test_unclosed_fence_raises():
    with pytest.raises(ParseError):
        lex("```python\nprint(1)\n")


def test_longer_fence_closes_outer():
    tokens = lex("```\n```\n````\n````\n")
    assert tokens[-1].kind is TokenKind.CODE_FENCE_CLOSE
    assert [tk.kind for tk in tokens] == [
        TokenKind.CODE_FENCE_OPEN, TokenKind.CODE_FENCE_CLOSE,
        TokenKind.CODE_FENCE_OPEN, TokenKind.CODE_FENCE_CLOSE]


def test_indented_code():
    assert kinds("    code line\n") == [(TokenKind.INDENTED_CODE, "code line")]


def test_admonition_kinds():
    for kind in ("note", "tip", "warn", "danger", "info"):
        tokens = lex(f"[{kind}] hello\n")
        assert tokens[0].kind is TokenKind.ADMONITION
        assert tokens[0].meta["kind"] == kind
        assert tokens[0].text == "hello"


def test_hr():
    assert kinds("---\n") == [(TokenKind.HR, "")]


def test_include_directive():
    assert kinds('{% include "guide/part.qd" %}\n') == [
        (TokenKind.INCLUDE, "guide/part.qd")]


def test_table_rows():
    assert kinds("| a | b |\n") == [(TokenKind.TABLE_ROW, "| a | b |")]


def test_footnote_def_and_definition():
    tokens = lex("[^note]: the body\n: a definition\n")
    assert tokens[0].kind is TokenKind.FOOTNOTE_DEF
    assert tokens[0].meta["name"] == "note"
    assert tokens[1].kind is TokenKind.DEFINITION


def test_blank_lines_are_blank():
    assert kinds("one\n\n\ntwo\n")[1:3] == [
        (TokenKind.BLANK, ""), (TokenKind.BLANK, "")]
