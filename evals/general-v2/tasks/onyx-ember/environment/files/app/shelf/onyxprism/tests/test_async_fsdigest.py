"""Targeted async-filesystem unit tests for the repaired onyxprism package.

These import the *installed* onyxprism, so they fail before the platform is
repaired (the factory stub raises on import) and pass once the working build is
installed into the default interpreter.
"""
import os
import tempfile

from onyxprism import checksum, fsdigest


def test_digest_matches_reference_single():
    with tempfile.TemporaryDirectory() as d:
        with open(os.path.join(d, "a.txt"), "wb") as fh:
            fh.write(b"alpha")
        with open(os.path.join(d, "b.bin"), "wb") as fh:
            fh.write(bytes(range(256)))
        got = fsdigest.digest(d)
        assert got["a.txt"] == checksum(b"alpha"), got
        assert got["b.bin"] == checksum(bytes(range(256))), got


def test_digest_empty_dir_is_empty_map():
    with tempfile.TemporaryDirectory() as d:
        assert fsdigest.digest(d) == {}