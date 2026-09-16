# `psutil.process_iter()` silently omits zombie processes

## Situation

`/app/src` is a shallow clone of the psutil library
(`https://github.com/giampaolo/psutil`) pinned at upstream commit
`1ae01d1210f73b411d38c0b7dc365727ae07608d`, checked out at detached HEAD. The
C extensions are already compiled and the project is installed in **editable
mode**, so every `python3` process in this container imports the library
straight from the tree:

```
python3 -c "import psutil; print(psutil.__file__)"   # /app/src/psutil/__init__.py
```

Editing a source file in `/app/src` takes effect on the next `import psutil`;
no rebuild or reinstall is needed for Python-level changes.

The environment has **no network** and runs on **one CPU**. `pytest` is
installed. `/app/src` is writable. `/opt`, `/tests` and `/solution` are
harness-owned: do not read or modify them.

## The bug

A process that has terminated but not yet been reaped is a *zombie*: it still
occupies an entry in the operating system's process table, still has a valid
PID, and is still fully reachable through the direct handle
`psutil.Process(pid)` — its status reads `'zombie'` and its other attributes
remain queryable. But **`psutil.process_iter()` does not yield it**. Zombie
processes silently vanish from the enumeration, and the iterator's internal
per-PID cache forgets them as if they had disappeared, so calling
`process_iter()` again omits them repeat times on end.

Any monitoring, load-balancing, restart or aggregation code that enumerates
processes with `process_iter()` therefore systematically undercounts the
process table whenever one of its entries is a zombie.

The bug is a defect in the enumeration logic itself — not in what the
operating system reports. The `/proc` table (and `psutil.pids()`, which reads
it) is complete; the omission happens between reading the table and yielding
the result.

## Deliverables and work order

Work in this order. The reproduction comes **first**, before any fix, and is a
deliverable in its own right.

1. **Write `/app/reproduce_zombie_skip.py`** — a deterministic reproduction of
   the bug, per the contract below. Run it now, against the tree as shipped:

   ```
   python3 /app/reproduce_zombie_skip.py
   ```

   The bug is present in this checkout, so it must fail: exit status non-zero
   and its output must begin with the line `BUG PRESENT: ...`.

2. **Fix the library in `/app/src`** so that the reproduction passes.

3. **Re-run the reproduction** — it must now exit `0` and print a line
   beginning `FIXED: ...`.

4. **Run the project's own enumeration test class** and leave it fully green:

   ```
   cd /app/src && python3 -m pytest tests/test_system.py -k TestProcessIter -q -p no:cacheprovider
   ```

### Reproduction contract (for `/app/reproduce_zombie_skip.py`)

- Self-contained: it may only use the standard library and `import psutil`
  from whichever psutil installation is active. It must not need root, the
  network, extra pip packages, or files outside itself.
- It must run to completion in well under 30 seconds and must be
  deterministic: no fixed sleeps to align with background processes, no
  dependence on which other processes happen to be running.
- It must put the reported behaviour on full display **through the public
  `process_iter()` API**, and the outcome must differ between the buggy and
  the correct code paths — which is exactly what the exit-code contract
  discriminates:

  - **Bug present:** exit non-zero and print one line to stdout starting
    `BUG PRESENT: ` followed by a short description of the omission.
  - **Bug fixed:** exit `0` and print one line to stdout starting
    `FIXED: ` followed by a short description.

  A "reproduction" that always passes, or that only checks the ordinary case
  every process satisfies, does not demonstrate the bug and is not a valid
  reproduction.

- The same script will be run by the grader in **two environments**: against a
  pristine pre-fix copy of the library (the harness's own isolated Python,
  which cannot see your tree) — where it must fail — and against your
  repaired tree — where it must pass. Write it so it needs no knowledge of
  those environments; the active installation is all it gets to see.

## Constraints

- No `git commit`, `git fetch`, `git remote`, `git checkout`/`reset` of the
  working tree, or any other history rewrite (there is no network anyway).
  Edit files in place.
- The verifier rejects changes to any tracked file other than the minimal set
  your fix needs, so change the sources only where the fix requires.
- Do not add, delete or rename files inside the repository; your reproduction
  lives at `/app/reproduce_zombie_skip.py`, outside the repository.
- Do not modify anything above `/app/src` (that includes
  `/opt/psutil-prefix`, `/opt/golden` and `/opt/prefix-venv`).

## What the verifier checks

1. **Provenance.** The tree is still at the pinned parent commit, the
   upstream fix commit is not reachable from the clone, the only tracked-file
   change is the minimal library change your fix needs, and `import psutil`
   really resolves to `/app/src`.
2. **Your reproduction**, run in both directions: it must fail against the
   pristine pre-fix copy of the library, and pass against your repaired tree.
3. **The project's own regression test** for this bug (taken from the
   fixed upstream version of the test suite and provided by the harness): it
   must pass against your repaired tree.
4. **Hidden cases** authored by the grader, exercising the same enumeration
   path from inputs the upstream regression test does not use: several
   simultaneous zombie-condition processes with different attribute sets, and
   retention of the iterator's internal cache across iterations.
5. **Regression guard:** a process that has genuinely disappeared must still
   be *dropped* from the enumeration — the fix must not turn silent omission
   of zombies into retention of dead processes.
6. **The project's own `TestProcessIter` class** passes end to end, so the
   fix broke nothing else in the enumeration API.

## What a correct deliverable looks like

- `/app/reproduce_zombie_skip.py`: your own deterministic reproduction,
  failing on the pre-fix library and passing on your repaired one.
- `/app/src`: the real psutil tree, fixed, with only the minimal tracked-file
  change the fix needs and `TestProcessIter` fully green.