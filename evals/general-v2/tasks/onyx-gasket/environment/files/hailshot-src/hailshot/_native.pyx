# cython: language_level=3
"""Compiled native fingerprint for the `hailshot` toolkit.

Implements FNV-1a (32-bit) over a file's bytes and is bit-for-bit identical
to :mod:`hailshot._fallback`.  It is a true compiled binary extension: after
an editable install the resolver must see ``hailshot._native`` backed by a
``.so`` on disk.
"""


def file_fingerprint(path, mode=0):
    """FNV-1a (32-bit) hash over the byte sequence of the file at *path*.

    FNV_OFFSET_BASIS = 0x811c9dc5 ; FNV_PRIME = 0x01000193
    :param mode: accepted for API compatibility, unused.
    :return: unsigned 32-bit integer.
    """
    cdef unsigned int h = 0x811C9DC5
    cdef Py_ssize_t n, i
    f = open(path, "rb")
    try:
        while True:
            chunk = f.read(65536)
            n = len(chunk)
            if n == 0:
                break
            for i in range(n):
                h ^= chunk[i]
                h = (h * 0x01000193) & 0xFFFFFFFF
    finally:
        f.close()
    return h