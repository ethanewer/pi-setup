"""Onyx Prism digest toolkit (default-interpreter package).

The factory install ships only a broken stub for this package; repairing the
platform reinstalls this working build into the default interpreter so that
`import onyxprism` loads the compiled (native) fast path.
"""
from . import _pure

try:
    from ._fast import checksum as _native_checksum
    backend = "native"
except Exception as _exc:  # noqa: BLE001
    _native_checksum = None
    backend = "fallback"

VERSION = "2.1.0-onyx"


def checksum(data):
    """FNV-1a 32-bit digest (native fast path, else pure fallback)."""
    fn = _native_checksum if _native_checksum is not None else _pure.checksum
    return fn(data)