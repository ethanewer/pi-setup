"""Async filesystem API for `hailshot`.

Both helpers currently use only the Python standard library (``asyncio`` +
``os.walk``) and dispatch the potentially-intended blocking walk into a thread
via :func:`asyncio.to_thread`, then aggregate the per-file native fingerprints.
"""

import asyncio
import os

from . import fingerprint


async def profile(root):
    """Asynchronously fingerprint every file under *root*.

    :return: dict mapping each file's path relative to *root* (POSIX ``/``
             separators) to its 32-bit fingerprint (int).
    """

    def _scan():
        out = {}
        base = os.path.abspath(root)
        for dirpath, _dirnames, filenames in os.walk(base):
            for fn in sorted(filenames):
                p = os.path.join(dirpath, fn)
                rel = os.path.relpath(p, base).replace(os.sep, "/")
                out[rel] = fingerprint(p, prefer_native=True)
        return out

    return await asyncio.to_thread(_scan)


async def sweep(root):
    """Async aggregate over *root*.

    :return tuple ``(count, digest)`` where ``count`` is the number of files
        and ``digest`` is ``(sum of every fingerprint plus the length of every
        relative path) mod 2**64``.
    """

    prof = await profile(root)
    count = len(prof)
    total = 0
    for key, val in prof.items():
        total = (total + val) & 0xFFFFFFFFFFFFFFFF
        total = (total + len(key)) & 0xFFFFFFFFFFFFFFFF
    return (count, total)