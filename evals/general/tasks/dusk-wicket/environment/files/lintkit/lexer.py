"""minipy tokenizer for the lintkit engine.

Splits a minipy source string into a flat token list.  Every token is a
4-tuple ``(kind, value, line, col)`` with ``line``/``col`` 1-based.  Comments
(``#`` to end of line) are kept as their own COMMENT tokens so that
suppression directives can be discovered later; blank lines are dropped
(a NEWLINE token is still emitted per real newline, but the parser skips
comment-only and blank lines).  Indentation is *not* encoded here: the parser
recovers block structure from the column of the first significant token on
each line.
"""

import re

NAME = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
NUMBER = re.compile(r"[0-9]+(?:\.[0-9]+)?")
STRING = re.compile(r'"(?:[^"\\\n]|\\.)*"|\'(?:[^\'\\\n]|\\.)*\'')
OP = re.compile(
    r"==|!=|<=|>=|\+=|-=|\*=|/=|%=|&&|\|\||[()\[\]{},:;=+\-*/%<>.]"
)


class LintError(Exception):
    """Raised on malformed minipy input."""


def tokenize(src):
    tokens = []
    pos = 0
    line = 1
    col = 1
    length = len(src)
    while pos < length:
        ch = src[pos]
        if ch in " \t":
            pos += 1
            col += 1
            continue
        if ch == "\n":
            tokens.append(("NEWLINE", "", line, col))
            pos += 1
            line += 1
            col = 1
            continue
        if ch == "#":
            start = pos
            while pos < length and src[pos] != "\n":
                pos += 1
            text = src[start:pos]
            tokens.append(("COMMENT", text, line, col))
            col += pos - start
            continue
        if ch in "\"'":
            m = STRING.match(src, pos)
            if not m:
                raise LintError("unterminated string at %d:%d" % (line, col))
            tok = m.group(0)
            tokens.append(("STRING", tok, line, col))
            pos = m.end()
            col += len(tok)
            continue
        if ch.isdigit():
            m = NUMBER.match(src, pos)
            tok = m.group(0)
            if "." in tok:
                value = float(tok)
            else:
                value = int(tok)
            tokens.append(("NUMBER", value, line, col))
            pos = m.end()
            col += len(tok)
            continue
        if ch.isalpha() or ch == "_":
            m = NAME.match(src, pos)
            tok = m.group(0)
            tokens.append(("NAME", tok, line, col))
            pos = m.end()
            col += len(tok)
            continue
        m = OP.match(src, pos)
        if m:
            tok = m.group(0)
            tokens.append(("OP", tok, line, col))
            pos = m.end()
            col += len(tok)
            continue
        raise LintError("unexpected character %r at %d:%d" % (ch, line, col))
    tokens.append(("EOF", "", line, col))
    return tokens
