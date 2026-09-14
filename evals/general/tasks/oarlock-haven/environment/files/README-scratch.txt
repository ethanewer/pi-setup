Task scratch notes (oarlock-haven)
==================================

Layout inside this container:

  /app/src                    shallow, detached clone of pytest-dev/pytest at
                              the pinned parent commit, installed in editable
                              mode (your working tree, a deliverable)
  /app/repro_failed_undo.py   your reproduction script (a deliverable you
                              must create; see the task instruction for the
                              exact contract)
  /opt/golden                 harness-owned upstream regression test
  /tests, /solution           harness-owned

Reminders:
  - There is no network. Everything you need is already installed.
  - Only source files under /app/src/src/_pytest/ may be modified.
  - Scratch files belong outside the repository (e.g. directly under /app/).
  - Verify your work with the project's own test runner from /app/src.