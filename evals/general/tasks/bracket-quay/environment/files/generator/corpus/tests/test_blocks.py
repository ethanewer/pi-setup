"""Renderer tests: block and inline nodes to HTML."""

from quaydoc import blocks, parser
from quaydoc.blocks import RenderContext
from quaydoc.links import LinkResolver
from quaydoc.toc import AnchorMap


class _Page:
    def __init__(self):
        self.anchor_map = AnchorMap()
        self.sections = []
        self.footnote_numbers = {}
        self.section_numbers = {}

    def __repr__(self):
        return "<Page>"


class _Site:
    pass


def ctx(page=None, resolver=None):
    return RenderContext(page or _Page(), _Site(), resolver or LinkResolver([], {}))


def render(text, **kw):
    page = kw.pop("page", _Page())
    document = parser.parse_document(text)
    page.anchor_map.assign(
        __import__("quaydoc.toc", fromlist=["build_sections"]).build_sections(
            document.headings))
    resolver = kw.pop("resolver", LinkResolver([], {}))
    c = RenderContext(page, _Site(), resolver)
    return blocks.render_blocks(document.blocks, c), page


def test_heading_renders_with_id():
    html, _ = render("## Hello World\n")
    assert html == '<h2 id="hello-world">Hello World</h2>'


def test_paragraph():
    html, _ = render("some **bold** text\n")
    assert "<p>some <strong>bold</strong> text</p>" in html


def test_heading_levels():
    html, _ = render("# A\n##### E\n")
    assert html.startswith('<h1 id="a">A</h1>')
    assert '<h5 id="e">E</h5>' in html


def test_list_rendering():
    html, _ = render("- a\n- b\n")
    assert "<ul><li><p>a</p></li><li><p>b</p></li></ul>" == html


def test_ordered_list():
    html, _ = render("1. x\n2. y\n")
    assert html.startswith("<ol>")


def test_blockquote():
    html, _ = render("> quoted\n")
    assert html == "<blockquote><p>quoted</p></blockquote>"


def test_code_block_with_lang():
    html, _ = render('```python\nprint(1)\n```\n')
    assert '<pre class="highlight"><code class="language-python">' in html
    assert "print(" in html
    assert "tok-" in html


def test_code_block_escaped():
    html, _ = render("```\n<a href=\"#\">\n```\n")
    assert "&lt;a" in html


def test_admonition_classes():
    html, _ = render("[danger] boom\n")
    assert 'class="admonition admonition-danger"' in html
    assert "Danger" in html


def test_table_renders():
    html, _ = render("| h |\n|---|\n| v |\n")
    assert "<table" in html and "<th>h</th>" in html and "<td>v</td>" in html


def test_footnote_ref_renders():
    html, page = render("text[^x]\n\n[^x]: the note\n")
    assert 'class="footnote-ref"' in html
    assert 'id="fnref-x"' in html


def test_footnote_section():
    from quaydoc import blocks as _blocks
    from quaydoc import parser as _parser
    from quaydoc.blocks import RenderContext
    from quaydoc.links import LinkResolver
    from quaydoc.toc import AnchorMap
    page = _Page()
    doc = _parser.parse_document("text[^x]\n\n[^x]: the note\n")
    ctx = RenderContext(page, _Site(), LinkResolver([], {}))
    section = _blocks.render_footnotes(doc.blocks, ctx)
    assert 'id="fn-x"' in section
    assert page.footnote_numbers["x"] == 1


def test_task_list_renders_checkbox():
    html, _ = render("- [x] done\n- [ ] todo\n")
    assert '<input type="checkbox" class="task-check" disabled checked>' \
        in html
    assert '<input type="checkbox" class="task-check" disabled>' in html


def test_definition_list():
    html, _ = render("Term\n: definition\n")
    assert "<dl" in html and "<dt>Term</dt>" in html and "<dd>definition</dd>" in html


def test_custom_heading_id():
    html, _ = render("## Wow {#custom-id}\n")
    assert 'id="custom-id"' in html


def test_emoji_expansion():
    html, _ = render("hello :smile:\n")
    assert "🙂" in html


def test_diagram_passthrough():
    html, _ = render('```mermaid\ngraph TD\nA --> B\n```\n')
    assert 'class="diagram diagram-mermaid"' in html
