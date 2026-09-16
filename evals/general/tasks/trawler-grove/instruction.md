# Git dependencies pinned to an explicit `refs/heads/...` or `refs/tags/...` revision are never checked out

## Situation

`/app/src` is a shallow, pinned clone of the poetry repository
(`https://github.com/python-poetry/poetry`) at upstream commit
`b8383e3cda4e7336eb9048b1e7388b5b914a4653`, checked out in detached HEAD.
The clone deliberately carries no git remotes, and the objects that exist in
its store are only the ones that commit needs.

The project is installed in editable mode into the virtualenv at
`/opt/poetry-venv`, so `import poetry` resolves to exactly the checked-out
tree and an edit takes effect immediately. pytest and pytest-mock are
installed in that venv. The repository's own pytest defaults live in
`/app/src/pyproject.toml`; they expect a parallel test runner, so run
everything with the project's own runner and the overrides below:

```
cd /app/src
/opt/poetry-venv/bin/python -m pytest <paths> --no-header -p no:randomly -o addopts=""
```

The project's own tests for the affected area are in `tests/vcs/git/` and
run fully offline in about a second; `tests/vcs/git/test_backend.py` is the
file that exercises the buggy behaviour.

## The bug

poetry can depend on a git repository, and such a dependency's source may
pin an explicit revision. Most revisions — a bare commit sha, `HEAD`, a
plain branch name, a plain tag name — are handled fine. But when the source
pins the **git plumbing form** of a ref — `refs/heads/<branch>` or
`refs/tags/<tag>`, exactly the strings git itself uses internally and that
`git rev-parse` accepts anywhere a ref is named — the clone path
misbehaves: it runs the equivalent of `git checkout refs/heads/main`
(respectively `git checkout refs/tags/v1.0`) and hands `git checkout` the
**prefixed string unchanged** instead of the bare branch or tag name.
`git checkout` does not accept the raw `refs/heads/...` form as the
argument it is being given, so the clone either fails outright
(`Failed to checkout ... at 'refs/heads/main'`-style errors) or does not end
up on the revision the user asked for.

The code intends to strip the `refs/heads/` / `refs/tags/` prefix before
checking out, but the stripping does not actually happen — the variable that
holds the revision is never assigned the stripped value. Non-prefixed
inputs are unaffected, which is why the bug shows up only for explicit
`refs/...` pins.

## Your task

Work against the checked-out tree at `/app/src`. Do it in this order:

1. **Write a failing reproduction first.** Create `/app/repro_test.py`: a
   pytest test file that, against the *current* code in `/app/src`, FAILS
   because it proves the raw `refs/heads/...` / `refs/tags/...` string is
   what gets handed to `git checkout` instead of the bare branch/tag name.
   Follow the project's own testing idiom for this area: the existing
   `tests/vcs/git/test_backend.py` tests mock the system-git calls rather
   than hitting a real remote — do the same. Keep it self-contained (no
   network, no real git repository needed), and make sure it can be run
   exactly as:

   ```
   /opt/poetry-venv/bin/python -m pytest /app/repro_test.py --no-header -p no:randomly -o addopts=""
   ```

2. **Confirm it fails** on the unchanged tree. That failing run is your
   reproduction of the reported bug.

3. **Fix the bug** in `/app/src` so an explicit `refs/heads/...` or
   `refs/tags/...` revision is normalized to the bare branch/tag name
   before `git checkout` runs, while non-prefixed revisions pass through
   exactly as before.

4. **Re-run your reproduction** — it must now PASS against the fixed tree.

5. Write `/app/summary.md` (plain text): the user-visible symptom, the root
   cause you found (including *why* the intended normalization silently did
   nothing), and precisely what you changed.

Then prove nothing else broke: the project's own git-backend test file must
stay green:

```
cd /app/src
/opt/poetry-venv/bin/python -m pytest tests/vcs/git/test_backend.py --no-header -p no:randomly -o addopts=""
```

## Constraints

- The deliverable is the repaired clone at `/app/src` plus the two files
  `/app/repro_test.py` and `/app/summary.md`.
- Keep the fix minimal and localised: the working tree inside the clone may
  end up differing from the pinned commit in exactly **one** tracked source
  file. Do not rewrite history, do not add git remotes, do not fetch, do not
  create commits, and do not add files or change tests or build files
  anywhere inside the repository. `/app/src` HEAD must stay at the pinned
  commit and the repository must gain no new git objects (the verifier
  checks the object store). Scratch experiments belong under `/tmp`, never
  in the tree.
- `/opt/golden`, `/opt/prefix`, `/tests` and `/solution` are harness-owned:
  do not read or modify them.

## What the verifier checks

1. Tree provenance: HEAD is still `b8383e3cda4e7336eb9048b1e7388b5b914a4653`,
   the working tree differs from the pinned commit in exactly the one
   tracked source file above, no stray untracked files exist inside the
   repository, and the upstream fix is absent from the repository's object
   store.
2. The virtualenv still resolves `import poetry` to `/app/src`.
3. `/app/repro_test.py` exists, fails when the same run is executed against
   a pristine pre-fix copy of the package (this is what makes the
   reproduction real), and passes against your repaired tree.
4. The project's own regression test for this bug — kept out of your tree at
   `/opt/golden` — passes on the repaired tree (4/4 parametrised cases).
5. The project's own existing git-backend suite passes in full.
6. Two hidden cases drive the same code path from ref inputs the upstream
   regression test does not use.