"""hailshot - an async filesystem fingerprint toolkit.

``fingerprint(path, prefer_native=True)`` returns a deterministic FNV-1a
(32-bit) hash of a file, computed by the compiled extension
(:mod:`hailshot._native`) when available and otherwise by the pure-python
fallback (:mod:`hailshot._fallback`).  The async helpers in
:mod:`hailshot.asyncfs` build on it.
"""

from . import _fallback

__version__ = "2.1.0"

try:
    from . import _native  # the compiled binary extension
except Exception:  # pragma: no cover - pristine state before rebuild
    _native = None


def fingerprint(path, prefer_native=True):
    """32-bit FNV-1a of the file at *path*.

    :param prefer_native: use the compiled extension if it is available.
    :returns: unsigned 32-bit int.
    """
    mod = _native if (prefer_native and _native is not None) else _fallback
    return mod.file_fingerprint(path)


from .asyncfs import profile, sweep  # noqa: E402  (order: native available)