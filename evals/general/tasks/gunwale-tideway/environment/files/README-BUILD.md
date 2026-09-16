# Build notes (gunwale-tideway)

This image hosts a real upstream checkout (git/git) at `/app/src`:

- Base: bench-base:ubuntu-24.04. Build toolchain: the standard Debian C
  toolchain (`build-essential`, OpenSSL/zlib/curl/expat development headers,
  libpcre2, gettext, file, unzip, plus `git` for the build's own helpers).
- The repository is cloned at build time with `git init` plus a single
  depth-1 fetch of the pinned parent commit (40-hex SHA, asserted), then
  detached at that commit. The object store therefore contains exactly one
  commit.
- The tree is built at the parent commit during image build (`make -j1`,
  ~2 minutes on one core), so the agent's own `make` runs are incremental
  and fully offline.
- The trial container has no network and `cpus = 1`.
- `/opt/golden/t5514-fetch-multiple.sh` (the project's own regression test
  for the defect, extracted from the fix commit through a throwaway clone)
  and `/opt/prefix/git` (a pristine pre-fix binary) are baked by the build;
  both are sha256-pinned in `/opt/pins` and read-only.
- `/app/src` is writable by root and by uid 1000.

Nothing in this file describes the defect under test; that is in
`instruction.md` and in the task contract.