"""Async filesystem digest utilities for Onyx Prism.

Walks a directory asynchronously and returns {filename: checksum} for every
regular file, using the installed onyxprism.checksum (native fast path when the
compiled backend is present).
"""
import asyncio
import os

from . import checksum


async def _scan(root):
    out = {}
    for entry in os.listdir(root):
        path = os.path.join(root, entry)
        if os.path.isfile(path):
            with open(path, "rb") as fh:
                out[entry] = checksum(fh.read())
    return out


def digest(root):
    """Asynchronously digest every regular file under `root`."""
    return asyncio.run(_scan(root))