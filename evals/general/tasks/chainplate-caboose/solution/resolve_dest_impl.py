"""The `_resolve_dest` helper for chainplate-caboose.

This module exists so the oracle can splice the helper's *source text* into
setuptools/archive_util.py without embedding a large string constant (whose
triple-quoted docstring and backslashes would fight the outer quoting).
When run as a module it also defines the function, so it can be imported for
a quick behavioural check; when the oracle reads it with pathlib the source
lines are used verbatim.

The text below is the upstream fix's helper (faithful reimplementation):
it is the single decision point that both archive drivers use to reject
member names that would escape the extraction directory.
"""
import ntpath
import os


def _resolve_dest(extract_dir, name):
    r"""
    Return the path where archive member `name` belongs under `extract_dir`,
    or None if the member would be written outside of `extract_dir`.

    Both the tar and zip formats specify '/' as the only path separator, so a
    backslash is never a legitimate separator in a member name and must not be
    allowed to act as one on Windows. Names that are absolute, drive-qualified,
    or UNC are rejected for the same reason.

    A directory member keeps its trailing separator, as callers rely on it to
    distinguish a directory from a file.

    >>> _resolve_dest('dest', 'sub/file.txt') == os.path.join('dest', 'sub', 'file.txt')
    True
    >>> _resolve_dest('dest', 'sub/dir/') == os.path.join('dest', 'sub', 'dir', '')
    True
    >>> _resolve_dest('dest', '/etc/passwd')
    >>> _resolve_dest('dest', '../escaped.txt')
    >>> _resolve_dest('dest', 'sub/../../escaped.txt')
    >>> _resolve_dest('dest', '..\\escaped.txt')
    >>> _resolve_dest('dest', 'sub\\..\\..\\escaped.txt')
    >>> _resolve_dest('dest', 'C:escaped.txt')
    >>> _resolve_dest('dest', '//server/share/escaped.txt')
    """
    if name.startswith('/') or '\\' in name or ntpath.splitdrive(name)[0]:
        return None

    parts = name.split('/')

    if '..' in parts:
        return None

    dest = os.path.join(extract_dir, *parts)

    # Belt and braces: confirm the result really does resolve within the root.
    root = os.path.realpath(extract_dir)
    try:
        if os.path.commonpath([root, os.path.realpath(dest)]) != root:
            return None
    except ValueError:
        # Paths on different drives are not comparable, and so not contained.
        return None

    return dest