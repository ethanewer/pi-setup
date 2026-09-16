# chainplate-brackish

You are working inside a real open-source codebase: **pylint** (the Python
static-analysis linter), checked out at a pinned commit in `/app/src` (the
working tree starts clean). There is a bug in this tree's lint rules. Your
job is to find it, fix it in the working tree, and prove the fix with the
project's own test tooling. You are deliberately **not** told which file or
function to change: localising the bug is part of the task.

## Environment

- pylint is installed editable from `/app/src` (Python 3.12), so edits you
  make to the sources under `/app/src/pylint/` take effect immediately — no
  rebuild, no reinstall.
- `pytest` and the project's own test suite are installed. The project's
  functional tests run with, from `/app/src`:
  `python3 -m pytest tests/test_functional.py -k <name> -q`.
- **There is no network** in this container. Everything needed is baked in.
  Do not attempt to `git fetch`, `pip install` or download anything.
- `cpus = 1`: one vCPU. Do not launch parallel test runs.
- The tree at `/app/src` is shallow (one commit) and detached; do not commit,
  fetch, or otherwise modify `.git`. Leave the working tree clean apart from
  your fix (delete scratch files before finishing).

## The bug (user-visible symptom)

pylint's `protected-access` check (message `W0212`) reads a protected class
member through `self.__class__` and wrongly reports it as a violation. Inside
an instance method, `self.__class__` is just another spelling of `type(self)`
— the identical access written as `type(self)._member` is already accepted by
the same check. The result: any method that reads a class attribute through
`self.__class__` gets a spurious warning and fails a clean lint run, while
the same code written with `type(self)` passes.

Reproduce it (a scratch file in `/tmp` — never leave scratch files in the
working tree):

```bash
cat > /tmp/repro.py <<'EOF'
class Widget:
    _attr = None
    def access_via_self_class(self):
        if self.__class__._attr is None:
            return self.__class__._attr
        return None
    def access_via_other_object_class(self, other):
        return other.__class__._attr
EOF
python3 -m pylint /tmp/repro.py --disable=all --enable=protected-access --score=n
```

On the buggy tree this prints **three** `W0212: Access to a protected member
_attr of a client class (protected-access)` entries — one for each of
`self.__class__._attr` (lines 4 and 5) and `other.__class__._attr`
(line 8) — and exits 4.

The correct behaviour: only the access through *another object's* class must
still warn. `self.__class__._attr` (both reads) must be **silent**.

## Requirements

1. Fix the tree so that on the reproduction above ONLY the `other.__class__`
   line (line 8) still emits `W0212`; both `self.__class__` reads must be
   clean. **Note:** pylint then still exits 4, because the legitimate
   `other.__class__` warning remains — that exit code is *expected* and is
   not a failure. The graded property is *which lines* warn, not "no output".
2. The fix must be principled, not an input special case: the same
   `self.__class__` reading pattern is accepted regardless of which name the
   method's first parameter has (`self`, `this`, `cls`, ... — it is the
   method's own first parameter), regardless of where the protected member is
   defined (including inherited members found through the MRO), and when
   mixed in the same method with `type(self)` accesses. Accesses through a
   *different* object's class (for example `other.__class__._member`) must
   **keep warning** in every one of those situations. Do not silence the
   check globally, do not disable the message, and do not add a config
   option that hides it.
3. Everything else must keep working exactly as before: linting at
   module level, other protected-access cases, and the rest of the project's
   checks. The project's own test suite must stay green.
4. The graded tree must be byte-identical to the pinned commit except for the
   **single source file where the bug lives**. Do not add, move, delete,
   rename or reformat any file; make no commits; do not modify `tests/`,
   `pyproject.toml` or any metadata/config file, and do not leave scratch or
   cache files behind. The grader compares every file's bytes against the
   pinned commit's own blobs, so cosmetic side-changes also fail.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/summary.md` — a non-empty write-up: what the bug was, what you
   changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with the one-liner above; use `/tmp` for scratch files,
   never the tree.
2. **Localise** the bug: the message is `W0212` (`protected-access`). Find
   where that message is emitted, and study why `self.__class__._attr` is
   treated as an access to "a client class" while `type(self)._attr`
   (a call to `type` on the method's first parameter) is exempted. The
   exemption for `type(self)` already exists in the code — the same idea must
   be extended to `self.__class__`. Understanding *why* the two are
   equivalent is required before you patch.
3. **Fix** with the smallest possible change in that one file; rerun the
   reproduction and confirm the W0212 set is down to just the
   `other.__class__` line.
4. **Prove nothing else broke**: run the project's own functional tests for
   the affected area, e.g. from `/app/src`:

   ```bash
   python3 -m pytest tests/test_functional.py -k "access_to_protected_members or access_member_before_definition or access_to__name__ or access_attr_before_def_false_positive" -q
   ```

   Every one of those passes on the pristine tree and must still pass after
   your fix.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert `HEAD` is still the pinned parent commit, and that every tracked
  file except the single source file where the bug lives is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/summary.md` to exist and be non-empty;
- rerun the reproduction and assert that the `W0212` lines are exactly the
  `other.__class__` one — none of the `self.__class__` reads may warn;
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden`; it was added by the upstream fix, so it is not in
  this tree) into the functional test suite and run it with the project's own
  `pytest` harness: it must pass, together with the project's existing
  `access/` functional tests, proving nothing else broke;
- run `python3 -m pylint` on **hidden cases** — other sources that reach the
  same code path from inputs the upstream regression test does not use
  (renamed first parameter, an inherited protected member, `type(self)` and
  `self.__class__` mixed in one method) — and assert the exact set of `W0212`
  lines each one must produce, including that `other.__class__` accesses
  still warn.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.