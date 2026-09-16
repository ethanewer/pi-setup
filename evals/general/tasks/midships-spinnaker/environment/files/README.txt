# midships-spinnaker — working environment

You are inside a container with the `requests` HTTP library installed.

- The `requests` package is installed EDITABLE from `/app/src` (its source
  lives in `/app/src/src/requests`). Edits you make to that source tree are
  picked up immediately by `import requests`.
- `/app/src` is a checked-out working copy of the upstream repository, pinned
  at one specific upstream commit; the git history it contains is exactly that
  one commit. Treat it as read-only HISTORY: do not create commits.
- Python 3.12 with `pytest` is installed, and `pytest-httpbin` is available so
  tests can run against a local httpbin server on 127.0.0.1 (there is no
  network and none is needed).
- All runtime dependencies are already installed. You do not need to run
  `pip install` or `git fetch`; neither will work (no network).