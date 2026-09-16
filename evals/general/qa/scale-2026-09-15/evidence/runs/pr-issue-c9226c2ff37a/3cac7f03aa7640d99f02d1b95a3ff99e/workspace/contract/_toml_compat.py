#!/usr/bin/env python3
"""TOML reader that works on any Python, not just 3.11+.

`tomllib` landed in 3.11. The gates used to fall back to a line-based parser
that stored `tags = ["a", "b"]` as one raw string, so callers iterating the
value walked its characters and emitted thousands of bogus errors (e.g.
`tag '[' not used by contract/verifier`). That silently corrupted every gate on
a 3.10 machine.

This module prefers the stdlib parser and otherwise parses the subset of TOML
that task.toml actually uses: sections, strings, integers, floats, booleans, and
single-line or multi-line arrays of those. It raises on anything outside that
subset rather than guessing.
"""
from __future__ import annotations

try:
    import tomllib as _tomllib
except ModuleNotFoundError:
    try:
        import tomli as _tomllib          # type: ignore
    except ModuleNotFoundError:
        _tomllib = None

__all__ = ['loads', 'load', 'read_toml', 'HAS_STDLIB_TOML']

HAS_STDLIB_TOML = _tomllib is not None

_NUM = ('0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '-', '+', '.')


class TomlSubsetError(ValueError):
    """Raised when input uses TOML features outside the supported subset."""


def _split_array(body: str):
    """Split a bracket-free array body into element tokens."""
    out, cur, quote, depth = [], '', None, 0
    i = 0
    while i < len(body):
        ch = body[i]
        if quote:
            cur += ch
            if ch == '\\' and i + 1 < len(body):
                cur += body[i + 1]
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
            cur += ch
        elif ch == '[':
            depth += 1
            cur += ch
        elif ch == ']':
            depth -= 1
            cur += ch
        elif ch == ',' and depth == 0:
            out.append(cur)
            cur = ''
        else:
            cur += ch
        i += 1
    if cur.strip():
        out.append(cur)
    return [o.strip() for o in out if o.strip()]


def _strip_comment(line: str) -> str:
    """Drop a trailing # comment that is not inside a string."""
    out, quote, i = '', None, 0
    while i < len(line):
        ch = line[i]
        if quote:
            out += ch
            if ch == '\\' and i + 1 < len(line):
                out += line[i + 1]
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
            out += ch
        elif ch == '#':
            break
        else:
            out += ch
        i += 1
    return out.rstrip()


def _scalar(tok: str):
    tok = tok.strip()
    if not tok:
        return ''
    if tok[0] in '"\'':
        if len(tok) >= 2 and tok[-1] == tok[0]:
            inner = tok[1:-1]
            if tok[0] == '"':
                return (inner.replace('\\n', '\n').replace('\\t', '\t')
                             .replace('\\"', '"').replace('\\\\', '\\'))
            return inner
        raise TomlSubsetError(f'unterminated string: {tok!r}')
    if tok.startswith('['):
        if not tok.endswith(']'):
            raise TomlSubsetError(f'unterminated array: {tok!r}')
        return [_scalar(e) for e in _split_array(tok[1:-1])]
    low = tok.lower()
    if low in ('true', 'false'):
        return low == 'true'
    if low in ('inf', 'nan', '+inf', '-inf'):
        raise TomlSubsetError(f'unsupported float token: {tok!r}')
    try:
        return int(tok)
    except ValueError:
        pass
    try:
        return float(tok)
    except ValueError:
        raise TomlSubsetError(f'unsupported value: {tok!r}')


def loads(text: str) -> dict:
    if _tomllib is not None:
        return _tomllib.loads(text)

    root: dict = {}
    section = root
    lines = text.splitlines()
    i = 0
    while i < len(lines):
        raw = lines[i]
        i += 1
        s = _strip_comment(raw).strip()
        if not s:
            continue
        if s.startswith('['):
            if not s.endswith(']'):
                raise TomlSubsetError(f'unterminated table header: {s!r}')
            if s.startswith('[['):
                raise TomlSubsetError(f'arrays of tables are unsupported: {s!r}')
            path = [p.strip().strip('"\'') for p in s[1:-1].split('.')]
            cur = root
            for part in path:
                cur = cur.setdefault(part, {})
                if not isinstance(cur, dict):
                    raise TomlSubsetError(f'conflicting table: {s!r}')
            section = cur
            continue
        if '=' not in s:
            raise TomlSubsetError(f'expected key = value: {s!r}')
        key, _, val = s.partition('=')
        key = key.strip().strip('"\'')
        val = val.strip()
        # join continuation lines for a multi-line array
        if val.startswith('[') and not _array_closed(val):
            while i < len(lines):
                nxt = _strip_comment(lines[i]).strip()
                i += 1
                val += ' ' + nxt
                if _array_closed(val):
                    break
            else:
                raise TomlSubsetError(f'unterminated array for key {key!r}')
        section[key] = _scalar(val)
    return root


def _array_closed(val: str) -> bool:
    depth, quote, i = 0, None, 0
    while i < len(val):
        ch = val[i]
        if quote:
            if ch == '\\':
                i += 2
                continue
            if ch == quote:
                quote = None
        elif ch in '"\'':
            quote = ch
        elif ch == '[':
            depth += 1
        elif ch == ']':
            depth -= 1
            if depth == 0:
                return True
        i += 1
    return False


def load(path) -> dict:
    from pathlib import Path
    return loads(Path(path).read_text(encoding='utf-8'))


def read_toml(path) -> dict:
    """Same as load(), kept for the name the gates already use."""
    return load(path)
