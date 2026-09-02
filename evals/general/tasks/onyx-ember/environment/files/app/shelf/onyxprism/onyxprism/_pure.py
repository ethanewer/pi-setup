"""Pure-python reference for the Onyx Prism digest algorithm.

Must stay bit-for-bit identical to onyxprism/_fast.pyx.
"""


def checksum(data):
    """FNV-1a 32-bit digest of `data` as an int."""

    if isinstance(data, bytes):
        b = data
    elif isinstance(data, str):
        b = data.encode("utf-8")
    else:
        b = bytes(data)

    h = 0x811C9DC5
    for ch in b:
        h ^= ch
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h