"""A tiny, dependency-free syntax highlighter.

Produces HTML with ``<span class="tok tok-KEYWORD">``-style classes.  The
token tables are intentionally modest; unknown languages fall back to plain
HTML escaping.  Good enough for documentation, and it keeps quaydoc
stdlib-only.
"""

from __future__ import annotations

import re

from quaydoc.util import escape_html

_KEYWORDS = {
    "python": {
        "and", "as", "assert", "async", "await", "break", "class",
        "continue", "def", "del", "elif", "else", "except", "finally",
        "for", "from", "global", "if", "import", "in", "is", "lambda",
        "nonlocal", "not", "or", "pass", "raise", "return", "try", "while",
        "with", "yield",
    },
    "bash": {"if", "then", "else", "elif", "fi", "for", "while", "do",
             "done", "case", "esac", "function", "in", "exit", "return",
             "local", "export", "set", "echo", "printf", "read", "shift"},
    "js": {"var", "let", "const", "function", "return", "if", "else",
           "for", "while", "do", "switch", "case", "break", "continue",
           "new", "typeof", "instanceof", "class", "extends",
           "try", "catch", "finally", "throw", "import", "export"},
    "json": set(),
    "ini": {"true", "false"},
    "html": {"html", "head", "body", "title", "meta", "link", "script",
             "style", "div", "span", "p", "a", "ul", "ol", "li", "h1",
             "h2", "h3", "h4", "h5", "h6", "pre", "code", "em", "strong",
             "img", "table", "tr", "td", "th", "form", "input"},
    "c": {"auto", "break", "case", "char", "const", "continue", "default",
          "do", "double", "else", "enum", "extern", "float", "for", "goto",
          "if", "int", "long", "register", "return", "short", "signed",
          "sizeof", "static", "struct", "switch", "union", "unsigned",
          "void", "volatile", "while"},
    "cpp": {"auto", "bool", "break", "case", "catch", "class", "const",
            "continue", "default", "delete", "do", "double", "else", "enum",
            "extern", "float", "for", "if", "int", "long", "namespace",
            "new", "private", "protected", "public", "return", "short",
            "signed", "sizeof", "static", "struct", "switch", "template",
            "throw", "try", "unsigned", "virtual", "void", "while"},
    "go": {"break", "case", "class", "const", "continue", "default", "else",
           "enum", "false", "for", "func", "if", "import", "in", "int",
           "interface", "nil", "package", "return", "string", "switch",
           "true", "var", "while"},
    "rust": {"as", "async", "await", "break", "case", "const", "continue",
             "default", "else", "enum", "fn", "for", "if", "impl", "import",
             "in", "let", "loop", "match", "mod", "move", "pub", "return",
             "struct", "trait", "true", "false", "use", "while"},
    "sql": {"select", "from", "where", "insert", "update", "delete",
            "create", "table", "index", "join", "left", "right", "inner",
            "outer", "on", "group", "by", "order", "having", "limit",
            "offset", "values", "set", "into", "drop", "alter", "add",
            "column", "primary", "key", "foreign", "references", "not",
            "null", "and", "or", "in", "between", "like", "distinct",
            "as", "asc", "desc"},
    "yaml": {"true", "false", "yes", "no", "on", "off", "null", "~"},
    "diff": {"diff", "index", "---", "+++", "@@"},
    "make": {"define", "else", "endif", "endef", "export", "ifdef",
             "ifeq", "ifndef", "ifneq", "include", "override", "private",
             "sinclude", "unexport"},
    "css": {"import", "media", "important", "not", "and", "or"},
    "toml": {"true", "false"},
}

_NUMBER_RE = r"\b(?:0x[0-9a-fA-F]+|\d+(?:\.\d+)?)\b"
_STRING_RE = r'(?:"(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|`(?:[^`\\]|\\.)*`)'
_CACHE = {}


def _master_re(lang):
    if lang in _CACHE:
        return _CACHE[lang]
    keywords = sorted(_KEYWORDS.get(lang, set()), key=len, reverse=True)
    if not keywords:
        _CACHE[lang] = None
        return None
    pattern = "|".join([
        f"(?P<string>{_STRING_RE})",
        f"(?P<number>{_NUMBER_RE})",
        r"(?P<keyword>\b(?:"
        + "|".join(re.escape(w) for w in keywords)
        + r")\b)",
    ])
    _CACHE[lang] = re.compile(pattern)
    return _CACHE[lang]


def guess_lang(code):
    """Guess a language name for a code sample (best effort)."""
    head = code[:2000]
    if "def " in head and ("import " in head or "return " in head):
        return "python"
    if "#!/bin/" in head or "$ " in head or "sudo " in head:
        return "bash"
    if head.lstrip().startswith(("{", "[")):
        return "json"
    if "<" in head and ">" in head and ("</" in head or "<!DOCTYPE" in head):
        return "html"
    if "SELECT " in head.upper() or "CREATE TABLE" in head.upper():
        return "sql"
    if "fn " in head or "let " in head or "struct " in head:
        return "rust"
    return "text"


def highlight(code, lang):
    """Highlight ``code`` for ``lang``; returns an HTML fragment."""
    if lang == "auto":
        lang = guess_lang(code)
    master = _master_re(lang or "text")
    if master is None:
        return escape_html(code)
    out = []
    pos = 0
    for m in master.finditer(code):
        out.append(escape_html(code[pos:m.start()]))
        group = m.lastgroup
        if group == "string":
            out.append(f'<span class="tok tok-string">{escape_html(m.group(0))}</span>')
        elif group == "number":
            out.append(f'<span class="tok tok-number">{escape_html(m.group(0))}</span>')
        else:
            out.append(f'<span class="tok tok-keyword">{escape_html(m.group(0))}</span>')
        pos = m.end()
    out.append(escape_html(code[pos:]))
    return "".join(out)


def register_language(name, keywords):
    """Add or replace a language's keyword table at runtime.

    The master tokeniser caches per language, so the cache entry is dropped
    to pick up the new table.
    """
    _KEYWORDS[name] = set(keywords)
    _CACHE.pop(name, None)
    return name


def known_languages():
    """Return the sorted language names with non-empty keyword tables."""
    return sorted(name for name, words in _KEYWORDS.items() if words)


def first_lines(code, count=3):
    """Return the first ``count`` non-blank lines of ``code`` (for previews)."""
    seen = []
    for line in code.splitlines():
        if line.strip():
            seen.append(line)
        if len(seen) >= count:
            break
    return "\n".join(seen)


def line_count(code):
    """Number of non-blank lines in ``code``."""
    return sum(1 for line in code.splitlines() if line.strip())


def comment_tokens(code, markers=("#", "//", "--")):
    """Split ``code`` into ``(is_comment, text)`` pairs, one per line.

    A line whose first non-blank token starts with one of ``markers`` is a
    comment line; everything else is code.  Inline trailing comments are
    kept as part of the code line: callers that need to strip them look for
    the first marker occurrence after the code position themselves.  Used
    to keep comment noise out of searchable page text.
    """
    pairs = []
    for line in code.splitlines():
        stripped = line.lstrip()
        is_comment = any(stripped.startswith(marker)
                         for marker in markers)
        pairs.append((is_comment, line + "\n"))
    return pairs
