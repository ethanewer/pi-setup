"""Pure-Python fallback implementation, used to sanity-check the native module.

This module has the identical FNV-1a (32-bit) contract as
:mod:`hailshot._native` so that :func:`hailshot.fingerprint` can be run in
either native or fallback mode and give bit-identical, deterministic results
on any input file.
"""


def file_fingerprint(path, mode=0):
    """FNV-1a (32-bit) hash over the byte sequence of the file at *path*.

    :param mode: accepted for API compatibility, unused.
    :return: unsigned 32-bit integer.
    """
    h = 0x811C9DC5
    with open(path, "rb") as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            for byte in chunk:
                h ^= byte
                h = (h * 0x01000193) & 0xFFFFFFFF
    return h