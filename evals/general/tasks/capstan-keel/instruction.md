# Cache cleanup must report the disk space actually reclaimed

## Situation

`/app/src` is a shallow, pinned clone of the `uv` project
(`https://github.com/astral-sh/uv`), checked out at an upstream commit in
which the bug described below is live. The tree is a real Cargo workspace: the
`uv` debug binary is already built at `/app/src/target/debug/uv` from this
exact checkout, and the Rust toolchain (1.98.0, pinned by the workspace's
`rust-toolchain.toml`) plus every dependency (the `Cargo.lock` is committed
in-tree) are installed. After you change sources, rebuild with:

```
cd /app/src && cargo build -p uv
```

There is **no network** at trial time; everything you need is already in the
image (`CARGO_NET_OFFLINE=true` is set, so any missing dependency fails loudly
instead of being fetched).

## The bug

`uv cache clean` and `uv cache prune` print a parenthesised figure after the
removal summary, e.g. `Removed 4 files (1.2MiB)`, which is supposed to be the
amount of disk space the command actually freed. That figure is wrong for two
common cache layouts:

1. **Hard-linked files.** Cached wheel archives are often hard links to files
   that still exist elsewhere (another cache, an environment, or a file you
   keep on disk). If the cache entry is a hard link to a file that remains on
   disk, deleting the cache entry frees **0 bytes**, but uv reports the entry's
   full logical length as if the storage were reclaimed. Files that are hard
   linked to each other *inside* the cache are double- or triple-counted too,
   inflating the reported savings beyond the storage that is really shared.
2. **Sparse or small files.** The reported bytes come from each file's logical
   length, not from the disk blocks it actually occupies. A sparse file's
   holes are charged as if they held data, so the printed figure can differ
   from the real footprint by gigabytes; small files are under-counted because
   they still occupy a whole block.

The proportion of the reported figure that is not really freed is not cosmetic:
`uv cache clean` output like `Removed 3 files (1.0MiB)` with `0B` actually
freed is exactly the failure mode. Deletion itself works correctly; only the
printed accounting is broken.

## Reproducing the failure

```
/app/probe_cache_accounting.sh         # hard-link scenario
/app/probe_cache_accounting.sh sparse  # sparse-file scenario
```

or by hand:

```
cd /tmp && rm -rf cx && mkdir -p cx/cache cx/home
head -c 1048576 /dev/zero > cx/retained.bin     # 1 MiB fully allocated file
ln cx/retained.bin cx/cache/cached.bin          # cache entry is a hard link
cd /tmp/cx && env HOME=/tmp/cx/home UV_CACHE_DIR=/tmp/cx/cache \
  /app/src/target/debug/uv cache clean
```

Observe that the printed figure matches what `stat` says the cache files *logically*
contain, not what removing them actually frees (the retained file keeps the
storage alive).

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that the parenthesised
figure reported by `uv cache clean` (and `uv cache prune`) is an estimate of
the disk space genuinely reclaimed:

- a file whose storage is shared with another surviving hard link (anywhere on
  the same filesystem) must contribute 0;
- a file whose storage is exclusively owned must contribute what its allocated
  disk blocks occupy, not its logical length;
- when files or directories were deleted, a figure must be printed even if the
  amount reclaimed is zero (e.g. `Removed 2 files (0B)` instead of printing
  nothing).

Keep the count (`Removed N files`) semantics and everything else about these
commands unchanged. The two commands must stay consistent with each other.

Drive your work with the resource you have on disk: the rebuilt binary and the
scenarios above. The project's own unit-test suites for the `uv-cache` and
`uv-fs` crates (`cd /app/src && cargo test -p uv-cache -q`) are green at this
commit and must stay green. You may add scratch tests of your own to
investigate, but nothing extra may remain in the tree.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place,
  and only tracked source files. Do not rewrite history, add remotes, fetch,
  or touch build files, lockfiles, docs, or the repository's own test corpus.
- Files under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier asserts that the tree is still at the pinned commit, that no
  unrelated files were modified and nothing was added, that a repair is in
  fact present, and that it changes **only** the crates involved in cache
  removal accounting and its call sites. It then builds the project and runs
  its own checks (including the upstream regression tests extracted at image
  build time into `/opt/golden/`) plus hidden end-to-end scenarios against the
  binary you leave in the image. Rebuild before you finish so the tree compiles
  and the binary you exercised is the one the verifier sees.

Deliverable: the repaired `/app/src` tree.