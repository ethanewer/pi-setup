# scantling-keel: environment notes

You are inside a container that holds a real upstream codebase: **SymPy**
(`sympy/sympy`), checked out at a pinned historical commit.

| Path | What it is |
| --- | --- |
| `/app/src` | The working tree you must modify. SymPy is installed from it **editable**, so `import sympy` picks up your edits immediately. It is a shallow, detached clone: the pinned commit is the only commit in the object store. |
| `/opt/prefix-sympy` | A second, pristine checkout of the same pinned commit (the build-time "pre-fix" reference). Read-only for you in spirit; never modify it. |
| `/opt/golden/` | The project's own regression test for this bug (extracted from the upstream fix commit at image build time). The verifier replants it into the tree and requires it to pass. |
| `/opt/pins/` | sha256 trust anchors recorded at image build time. |
| Python | 3.12.13; `mpmath==1.3.0`, `pytest==9.1.1`, `hypothesis==6.168.0` installed; `pip install -e /app/src` already done. |

No network. One vCPU. The working tree must stay detached at the pinned
commit (no commits) and, apart from the source file(s) where the bug lives,
byte-identical to it.

See `instruction.md` for the task.