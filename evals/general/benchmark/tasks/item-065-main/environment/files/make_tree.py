#!/usr/bin/env python3
"""Deterministic source tree builder for the item-065 shard task.

Usage: make_tree.py <root>

Creates (under <root>, replacing any prior content) a fixed, heterogeneous,
deterministic filesystem tree: nested dirs, empty dirs, UTF-8 text, a binary
blob, and files with embedded null bytes / tabs.  The exact bytes are
intentional: a correct shard round-trip must restore them byte-for-byte.
"""
import os
import sys

TREE = [
    ("a.txt", b"hello world\n"),
    ("b1/b.txt", b"line one\nline two\nline three\n"),
    ("b1/sub/c.json", b'{\n  "ok": true,\n  "n": 42\n}\n'),
    ("b1/empty_dir/", None),
    ("b2/d.txt", b"nesting a bit deeper\n\x00\x01\x02tab\tend\n"),
    ("b2/sub/deeper/file.txt",
     b"The quick brown fox jumps over the lazy dog. " * 20 + b"\n"),
    ("unicode/h\xc3\xa9llo.txt", b"h\xc3\xa9llo w\xc3\xb6rld \xcf\x86\n"),
    ("data.bin", bytes(range(256))),
    ("empty/", None),
    ("empty/nested/empty2/", None),
    ("top-level empty.txt", b""),
]


def _rmtree(root):
    if not os.path.exists(root):
        return
    for base, dirs, files in os.walk(root, topdown=False):
        for name in files:
            os.unlink(os.path.join(base, name))
        for name in dirs:
            try:
                os.rmdir(os.path.join(base, name))
            except OSError:
                pass
    try:
        os.rmdir(root)
    except OSError:
        pass


def build(root):
    _rmtree(root)
    for rel, data in TREE:
        path = os.path.join(root, rel)
        os.makedirs(os.path.dirname(path) or root, exist_ok=True)
        if data is None:
            os.makedirs(path, exist_ok=True)
        else:
            with open(path, "wb") as f:
                f.write(data)


if __name__ == "__main__":
    build(sys.argv[1])