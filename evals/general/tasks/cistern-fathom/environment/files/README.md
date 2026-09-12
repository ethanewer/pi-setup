# cistern-fathom environment notes

- Upstream checkout: `/app/src` — a git repository detached at the exact
  historical revision this task targets. The genuine bug is present; the
  upstream fix is not.
- `werkzeug` is installed *editable* from that checkout
  (`/app/src/src/werkzeug`), so plain `python3` imports resolve to the source
  tree and your edits take effect immediately, without any reinstall.
- `pytest` and the project's own dev/test dependencies (its
  `tests/conftest.py` imports `pytest`, `pytest-xprocess`'s `xprocess` module
  and `ephemeral_port_reserve`) are installed, pinned.
- There is no network at trial time. Everything you need is already in the
  image; do not try to download anything, and do not re-clone `/app/src`.
- The repository is graded for provenance: leave `HEAD` where it is and write
  any scratch files under `/tmp`, never inside `/app/src`.