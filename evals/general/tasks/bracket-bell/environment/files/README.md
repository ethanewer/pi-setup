# bracket-bell environment notes

These files are copied into the trial image at `/app` alongside the real
curl source tree at `/app/src` (pinned, already configured and built). See
`/app/instruction.md` for the actual task.

Quick reference for the environment:

- `/app/src` — real upstream `curl/curl` source tree (a single pinned commit,
  shallow clone, HEAD is detached). Already configured with
  `./configure --with-openssl --enable-debug` and built; the test harness
  under `/app/src/tests` is built too.
- `/app/src/src/curl` — the built curl binary (debug build).
- `make -C /app/src` — incremental rebuild (fast: only changed files).
- `cd /app/src/tests && ./runtests.pl -n <test-selection>` — run the
  project's own test suite for selected test numbers.
- `gdb` is installed for localisation; `strace` too.
- python3.12 is the interpreter used to run the local loopback HTTP server of
  the reproducer.
- The container has NO network: everything needed is already on disk. Do not
  try to download anything.