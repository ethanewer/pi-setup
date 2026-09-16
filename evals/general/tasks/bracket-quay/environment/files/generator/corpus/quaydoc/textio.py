"""Robust text-file reading for quaydoc source documents.

Source files in the wild arrive as UTF-8, UTF-8 with a BOM, UTF-16, or
Latin-1.  The lexer expects plain, BOM-free, ``\\n``-terminated text, so
:func:`read_utf8_text` normalises everything at the boundary.
"""

from __future__ import annotations

import codecs

from quaydoc.errors import ParseError

_BOM_UTF8 = codecs.BOM_UTF8
_BOM_UTF16_LE = codecs.BOM_UTF16_LE
_BOM_UTF16_BE = codecs.BOM_UTF16_BE


def _decode(raw: bytes, path: str) -> str:
    if raw.startswith(_BOM_UTF8):
        return raw[len(_BOM_UTF8):].decode("utf-8")
    if raw.startswith(_BOM_UTF16_LE) or raw.startswith(_BOM_UTF16_BE):
        return raw.decode("utf-16")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        return raw.decode("latin-1")


def normalize_newlines(text: str) -> str:
    """Normalise ``\\r\\n`` and lone ``\\r`` to ``\\n``."""
    return text.replace("\r\n", "\n").replace("\r", "\n")


def read_utf8_text(path: str) -> str:
    """Read ``path`` as text, handling BOMs and alternate newlines.

    Raises :class:`ParseError` when the file cannot be read at all.
    """
    try:
        with open(path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        raise ParseError(str(path), None, f"cannot read file: {exc}") from exc
    return normalize_newlines(_decode(raw, str(path)))


def sniff_language(ext: str, text: str) -> str:
    """Best-effort language guess for fenced code without an explicit lang.

    Looks at a handful of tell-tale tokens; returns ``"text"`` when nothing
    matches.
    """
    head = text[:4000]
    if ext == ".py" or "def " in head or "import " in head:
        return "python"
    if ext in (".sh", ".bash") or "#!/bin/bash" in head:
        return "bash"
    if ext in (".json",) or head.lstrip().startswith("{"):
        return "json"
    if ext in (".yml", ".yaml", ".toml"):
        return "ini"
    if ext in (".html", ".htm", ".xml"):
        return "html"
    return "text"
