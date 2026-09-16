# ballast-reach — environment notes

- `/app/src` is a real, shallow clone of **pypa/setuptools** checked out
  detached at one pinned commit; the working tree is clean. The only
  generated artifact present is `setuptools.egg-info/` from the build-time
  `pip install -e '.[test]'` step.
- `import setuptools` resolves to `/app/src/setuptools` (editable install),
  so editing the tree immediately changes installed behaviour.
- Python 3.12.13, git 2.47.3, pytest **8.4.2** (do not change the pytest
  version: the repository's own `pytest.ini` turns warnings into errors and
  other versions break collection).
- There is **no network** in this container; nothing you need is missing.
- Do not run `git add/commit/fetch/checkout/reset/rebase/clean` on this
  checkout and do not edit anything under `/app/src/.git` — the grader
  compares the final working tree byte-for-byte against the pinned commit.
- Scratch files and test projects belong in `/tmp`, never in `/app/src`.

## Runtime integrity (verifier trust anchor)

The verifier runs in the SAME container the agent worked in (shared
verifier), so the task rejects any change to the interpreter or package
code outside `/app/src` — a sitecustomize shim, a replaced `python3`,
an injected site-packages module, or an edited `/opt/golden` test file
would otherwise pass the behavioural checks with the tree untouched.
The image's `/opt/runtime.manifest` was hashed at build time and that
fingerprint is committed at `tests/runtime-fingerprint.txt`:

```
sha256sum < /opt/runtime.manifest   # build-time manifest -> fingerprint
```

If you change anything that touches `/usr/local`, the manifest (and the
committed fingerprint) MUST be regenerated:

```bash
docker build -t <img> tasks/ballast-reach/environment
docker run --rm <img> bash -c 'cat /opt/runtime.manifest | sha256sum' \
  > tasks/ballast-reach/tests/runtime-fingerprint.txt
```

The environment is fully pinned (`environment/files/deps-pinned.txt`, the
complete wheel freeze of the validated build minus the editable
setuptools line — never re-add that line: `pip install -r` would clone
the upstream repo into `/app/src/src` and hijack the editable install),
so a rebuild is byte-deterministic and the fingerprint stays valid until
the Dockerfile installs are deliberately changed. Staleness shows up as
oracle reward 0 in `tools/verify_new_task.sh`.