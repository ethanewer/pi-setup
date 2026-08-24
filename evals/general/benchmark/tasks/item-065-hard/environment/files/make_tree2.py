#!/usr/bin/env python3
"""Deterministic source tree builder for item-065-hard.

Usage: make_tree2.py <root>

Builds a much larger, deeper, more heterogeneous tree than the medium task:
5 levels of nesting, many files, empty dirs scattered at every depth, dotted
filenames, spaces, a dash-prefixed name, UTF-8 text, and two binary blobs.
Round-trip must restore every byte and every (possibly empty) directory.

The whole tree is generated from fixed data so the verifier can rebuild the
expected tree deterministically.
"""
import os
import sys

BLOB_A = bytes(range(256)) * 3 + b"\x00\xffbinary!\n"
BLOB_B = bytes([(i * 37) % 256 for i in range(512)])


def _tree():
    t = [
        ("0-root.txt", b"root marker\n"),
        ("alpha/one.txt", b"1\n"),
        ("alpha/two.txt", b"2\n" * 5),
        ("alpha/sub/three.txt", b"three\n"),
        ("alpha/sub/deeper/four.txt", b"four four four\n"),
        ("alpha/sub/deeper/even/deeper/five.txt", b"five\n" * 20),
        ("alpha/empty-d1/", None),
        ("alpha/empty-d1/empty-d2/", None),
        ("beta/dash-file.txt", b"dash\n"),
        ("beta/-leading-dash.txt", b"careful\n"),
        ("beta/space file.txt", b"spaces\n"),
        ("beta/sub/meta.json", b'{"should":"not-rot","n":3}\n'),
        ("beta/sub/nested/empty/", None),
        ("gamma/g1/g2/g3/g4/g5/deep-target.txt", b"deep\n"),
        ("unicode/na\xc3\xafve - caf\xc3\xa9.json", b'{"ok":1}\n'),
        ("blobs/blob-a.bin", BLOB_A),
        ("blobs/sub/blob-b.bin", BLOB_B),
        ("blobs/blob-c.txt", b"plain text\n"),
        ("zz/tail.txt", b"tail\n"),
        ("zz/", None),
    ]
    return t


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
    for rel, data in _tree():
        path = os.path.join(root, rel)
        parent = os.path.dirname(path) or root
        os.makedirs(parent, exist_ok=True)
        if data is None:
            os.makedirs(path, exist_ok=True)
        else:
            with open(path, "wb") as f:
                f.write(data)


if __name__ == "__main__":
    build(sys.argv[1])