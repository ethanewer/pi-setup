#!/usr/bin/env python3
"""Apply the cache space-accounting fix to an astral-sh/uv checkout.

The fix has two parts, both Observable through the CLI output of
`uv cache clean` / `uv cache prune`:

1. crates/uv-cache/src/removal.rs -- Removal::add_file must account for the
   disk space actually reclaimed by deleting the file: its allocated blocks
   (st_blocks * 512), and only while this path is the file's final hard link
   on the filesystem.  A surviving hard link keeps the storage alive, so the
   contribution is 0.  (The public field name `logical_bytes` is kept; only
   the semantics change.)

2. crates/uv/src/commands/cache_clean.rs and crates/uv/src/commands/cache_prune.rs
   -- the printed figure is currently gated on the byte totals: when nothing
   was reclaimed the parenthesised `(X)` figure is omitted entirely.  The gate
   must be on whether anything was deleted (files or directories), so e.g.
   deleting a retained hard link prints `Removed 2 files (0B)`.

Each edit is asserted against the exact pre-fix text so the script fails
loudly (rather than silently no-oping) if the tree is not the expected state.
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(sys.argv[1] if len(sys.argv) > 1 else "/app/src")

REMOVAL = ROOT / "crates/uv-cache/src/removal.rs"
CACHE_CLEAN = ROOT / "crates/uv/src/commands/cache_clean.rs"
CACHE_PRUNE = ROOT / "crates/uv/src/commands/cache_prune.rs"


def edit(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if old not in text:
        raise SystemExit(f"FATAL: expected context not found in {path} ({label})")
    if text.count(old) != 1:
        raise SystemExit(f"FATAL: expected context is ambiguous in {path} ({label})")
    path.write_text(text.replace(old, new, 1))
    print(f"patched {path.relative_to(ROOT)}: {label}")


# ---- 1. removal.rs: block-based, hard-link-aware accounting ----------------
edit(
    REMOVAL,
    "use std::io;\nuse std::path::Path;\n",
    "use std::io;\nuse std::path::Path;\n#[cfg(unix)]\nuse std::os::unix::fs::MetadataExt;\n",
    "import MetadataExt (allocated-block accessor)",
)

helper = """/// Estimate the disk space reclaimed by removing a regular file: its
/// allocated blocks (512-byte units), and only when this path is the file's
/// final hard link on the filesystem.  A surviving hard link anywhere on the
/// filesystem keeps the storage alive, so deleting this path frees nothing.
#[cfg(unix)]
fn file_size(metadata: &std::fs::Metadata) -> u64 {
    if metadata.nlink() == 1 {
        metadata.blocks().saturating_mul(512)
    } else {
        0
    }
}

#[cfg(not(unix))]
fn file_size(metadata: &std::fs::Metadata) -> u64 {
    metadata.len()
}

impl Removal {"""

edit(
    REMOVAL,
    "impl Removal {",
    helper,
    "block-based file_size helper",
)

edit(
    REMOVAL,
    "        self.logical_bytes += metadata.len();",
    "        self.logical_bytes += file_size(metadata);",
    "add_file accounts allocated blocks, not logical length",
)

# ---- 2. cache_clean.rs / cache_prune.rs: gate the figure on deletions -------
for f in (CACHE_CLEAN, CACHE_PRUNE):
    edit(
        f,
        "    if summary.logical_bytes > 0 || reported_bytes > 0 {",
        "    if summary.num_files > 0 || summary.num_dirs > 0 {",
        "print the reclaimed figure whenever anything was removed",
    )

print("done")