# wale-beacon build notes

This image is produced from the `environment/Dockerfile` at image build time;
`files/` is copied to `/app/` by the final `COPY`.

At build time the Dockerfile:

- clones the real upstream repository `pytorch/vision` at the pinned parent
  commit (shallow, single-commit object store) into `/app/src`;
- creates the venv at `/app/env` with the pinned official CPU wheels
  `torch==2.14.0+cpu` and `torchvision==0.29.0+cpu` plus `pytest`;
- makes the installed torchvision package's transform logic resolve to the
  `/app/src` tree via a symlink (the compiled image codec stays in the wheel);
- bakes a pristine pre-fix copy of the buggy module at `/opt/prefix`;
- extracts the project's own regression test for the bug into `/opt/golden`
  through a throwaway clone of the fix commit, then deletes that clone;
- records sha256 trust anchors under `/opt/pins`.

Nothing in `files/` is shipped to the trial as editable task content beyond what
the agent is told in `instruction.md`; this file is documentation.