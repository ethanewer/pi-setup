# onyxprism (Onyx Prism)

Primary-disk digest toolkit for the Onyx Forge telemetry platform.

- `onyxprism.checksum(data)` — FNV-1a 32-bit digest (native fast path in
  `_fast.pyx`, pure-python reference in `_pure.py`).
- `onyxprism.fsdigest.digest(root)` — asynchronously digest a directory tree.
- `tests/` — targeted async-filesystem unit tests.

The factory image installs only a *broken stub* of this package for the default
interpreter; the real, editable build lives here. Recompile the Cython
extension and install this tree to repair the platform.