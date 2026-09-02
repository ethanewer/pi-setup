"""Targeted async filesystem unit tests for the `hailshot` toolkit.

These are the repository's own targeted tests: they only pass once the edited
tree (which exposes the new async ``profile`` capability) is actually
installed such that the default interpreter imports the **compiled** extension.
Runs under plain ``pytest`` / ``unittest`` (stdlib ``asyncio`` only).
"""

import asyncio
import os
import tempfile
import unittest

import hailshot


def _make_tree(root):
    root = os.path.abspath(root)
    os.makedirs(os.path.join(root, "a", "b"), exist_ok=True)
    with open(os.path.join(root, "a.bin"), "wb") as f:
        f.write(b"hello world")
    with open(os.path.join(root, "a", "note.txt"), "wb") as f:
        f.write(b"123456789")
    return root


class TestAsyncFS(unittest.TestCase):
    def test_native_is_compiled(self):
        self.assertIsNotNone(hailshot._native, "native extension must be built")
        self.assertTrue(hailshot._native.__file__.endswith(".so"))

    def test_profile_matches_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            root = _make_tree(td)
            prof = asyncio.run(hailshot.profile(root))
            fall = hailshot.fingerprint(
                os.path.join(root, "a", "note.txt"), prefer_native=False
            )
            self.assertEqual(prof["a/note.txt"], fall)
            self.assertEqual(set(prof.keys()), {"a.bin", "a/note.txt"})

    def test_sweep_count_and_digest(self):
        with tempfile.TemporaryDirectory() as td:
            root = _make_tree(td)
            count, digest = asyncio.run(hailshot.sweep(root))
            self.assertEqual(count, 2)
            # digest = sum(fp + len(rel)) mod 2**64 over both files
            prof = asyncio.run(hailshot.profile(root))
            expect = (prof["a.bin"] + len("a.bin")) + (
                prof["a/note.txt"] + len("a/note.txt")
            )
            self.assertEqual(digest, expect & 0xFFFFFFFFFFFFFFFF)


if __name__ == "__main__":
    unittest.main()