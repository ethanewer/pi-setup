"""Parser unit tests: token runs to block nodes."""

import pytest

from quaydoc import parser
from quaydoc.errors import ParseError, SourceError
from quaydoc.nodes import (
    Admonition, BlockQuote, CodeBlock, DefinitionList, FootnoteDef, Heading,
    HrBlock, List, ListItem, Paragraph, Table,
)


def parse(text, **kw):
    return parser.parse_document(text, **kw)


def blocks_of(text):
    return parse(text).blocks


def test_paragraph_joins_lines():
    blocks = blocks_of("first line\nsecond line\n")
    assert len(blocks) == 1
    assert isinstance(blocks[0], Paragraph)


def test_headings_list():
    doc = parse("## A\n### B\n# C\n")
    assert doc.headings == [(2, "A"), (3, "B"), (1, "C")]


def test_blank_separates_paragraphs():
    blocks = blocks_of("one\n\ntwo\n")
    assert len(blocks) == 2


def test_unordered_list():
    blocks = blocks_of("- a\n- b\n")
    assert len(blocks) == 1
    node = blocks[0]
    assert isinstance(node, List)
    assert [item.ordered for item in node.items] == [False, False]
    assert len(node.items[0].blocks) == 1


def test_nested_list():
    blocks = blocks_of("- a\n  - b\n  - c\n- d\n")
    node = blocks[0]
    assert len(node.items) == 2
    inner = node.items[0].blocks[1]
    assert isinstance(inner, List)
    assert [i.blocks[0] for i in inner.items]


def test_mixed_ordered_unordered():
    blocks = blocks_of("- a\n1. b\n")
    node = blocks[0]
    assert [i.ordered for i in node.items] == [False, True]


def test_blockquote_recursive():
    blocks = blocks_of("> some text\n> more text\n")
    node = blocks[0]
    assert isinstance(node, BlockQuote)
    assert isinstance(node.children[0], Paragraph)


def test_fenced_code_block():
    blocks = blocks_of("```python\nprint(1)\n```\n")
    node = blocks[0]
    assert isinstance(node, CodeBlock)
    assert node.lang == "python"
    assert node.text == "print(1)"


def test_indented_code_block():
    blocks = blocks_of("    const a = 1;\n")
    node = blocks[0]
    assert isinstance(node, CodeBlock)
    assert node.lang is None
    assert node.text == "const a = 1;"


def test_admonition_with_text():
    blocks = blocks_of("[warn] Careful now\n")
    node = blocks[0]
    assert isinstance(node, Admonition)
    assert node.kind == "warn"


def test_hr_block():
    assert isinstance(blocks_of("a\n\n---\n")[1], HrBlock)


def test_table_with_header():
    blocks = blocks_of("| a | b |\n|---|---|\n| 1 | 2 |\n")
    node = blocks[0]
    assert isinstance(node, Table)
    assert node.headers == ["a", "b"]
    assert node.rows == [["1", "2"]]


def test_table_without_header():
    blocks = blocks_of("| 1 | 2 |\n| 3 | 4 |\n")
    node = blocks[0]
    assert node.headers == []
    assert node.rows == [["1", "2"], ["3", "4"]]


def test_footnote_def():
    blocks = blocks_of("[^note]: body text\n")
    node = blocks[0]
    assert isinstance(node, FootnoteDef)
    assert node.name == "note"
    assert node.text == "body text"


def test_definition_list():
    blocks = blocks_of("Term one\n: definition one\n: definition two\n")
    node = blocks[0]
    assert isinstance(node, DefinitionList)
    assert node.items["Term one"] == ["definition one", "definition two"]


def test_frontmatter_parsed():
    doc = parse("---\ntitle: Hello\norder: 3\n---\nbody\n")
    assert doc.frontmatter["title"] == "Hello"
    assert doc.frontmatter["order"] == 3


def test_no_frontmatter():
    assert parse("body\n").frontmatter == {}


def test_include_directive_expands(tmp_path):
    inc = tmp_path / "part.qd"
    inc.write_text("## From include\n", encoding="utf-8")

    def includer(path, source):
        return inc.read_text(encoding="utf-8")

    doc = parse("before\n{% include \"part.qd\" %}\n", includer=includer)
    assert isinstance(doc.blocks[1], Heading)


def test_include_missing_raises():
    def includer(path, source):
        raise SourceError(f"{source}: missing {path}")

    with pytest.raises(SourceError):
        parse('{% include "nope.qd" %}\n', includer=includer)


def test_unknown_directive_raises():
    with pytest.raises(ParseError):
        parse("{% frobnicate %}\nbody\n{% endfrobnicate %}\n")


def test_generic_admonition_directive():
    blocks = blocks_of("{% note %}\nhello\n{% endnote %}\n")
    node = blocks[0]
    assert isinstance(node, Admonition)
    assert node.kind == "note"


def test_heading_custom_id():
    blocks = blocks_of("## Title {#my-id .heavy}\n")
    node = blocks[0]
    assert node.clean_title == "Title"
    assert node.custom_id == "my-id"
    assert node.classes == ["heavy"]


def test_heading_no_suffix():
    node = blocks_of("## Plain\n")[0]
    assert node.custom_id is None
    assert node.clean_title == "Plain"
