# cython: language_level=3
#
# Onyx Prism native digest backend. Pure Cython (no numpy dependency).
# Implements FNV-1a 32-bit so it must agree bit-for-bit with the pure-python
# reference in onyxprism/_pure.py for any input.
from libc.stdint cimport uint32_t, uint8_t

DEF FNV_OFFSET = 0x811c9dc5
DEF FNV_PRIME = 0x01000193


cdef uint32_t _fnv1a(bytes b):
    cdef uint32_t h = FNV_OFFSET
    cdef unsigned char c
    for c in b:
        h = (h ^ <uint32_t>c) * FNV_PRIME
    return h


def checksum(data):
    """Return the FNV-1a 32-bit digest of `data` as an int.

    Accepts bytes or str (str is encoded UTF-8). Matching _pure.checksum.
    """
    if isinstance(data, bytes):
        return _fnv1a(data)
    if isinstance(data, str):
        return _fnv1a(data.encode("utf-8"))
    return _fnv1a(bytes(data))