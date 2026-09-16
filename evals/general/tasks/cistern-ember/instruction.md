# Streaming async templates leak async generators

This is a debugging task inside a **real upstream codebase**: a working copy of
the Jinja2 template engine at a specific commit is installed in `/app/src`.
The tree contains a genuine bug. Your job is to reproduce it, localise its
root cause in the library source, repair the source, and keep the library's
own test suite green.

## Environment

- `/app/src` is a full working copy of the real Jinja2 tree (Python 3.12
  compatible), checked out at one specific commit. It is a clean regular
  directory: **there is no git history and no `.git` directory** — nothing to
  diff against and nothing to bisect, just the source.
- Python 3.12 with the packages the project's own test suite needs
  (`pytest==7.4.3`, `pytest-timeout==2.4.0`, `trio==0.34.0`,
  `MarkupSafe==3.0.3`) installed. The library itself is the tree: `import
  jinja2` resolves to `/app/src/src/jinja2`, and any command below also sets
  `PYTHONPATH=/app/src/src` explicitly so nothing can shadow the tree.
- There is **no network** in this container: you cannot re-fetch anything, so
  do not delete or regenerate the tree, and expect every pip install to fail.

## The failing behaviour

An application renders a template in async mode (`enable_async=True`) and
consumes its output **incrementally** — streaming a page, `{% include %}`ing a
partial, or rendering through template inheritance. Whenever iteration stops
before the stream is fully drained, the async generators underneath the
rendering are never closed. Most runtimes ignore that; event-loop runtimes
that actively police resource cleanup report diagnostics such as:

```
ResourceWarning: Async generator '<<template>>.root' was garbage collected
before it had been exhausted. ...
```

and applications that treat warnings as errors start crashing on perfectly
normal streaming code. The leak is invisible under plain asyncio, because
asyncio's shutdown machinery closes leftover generators silently. It only
shows up under a strict runtime — like trio, which is installed here.

Observe it:

```bash
cd /app/src && PYTHONPATH=/app/src/src python3 /app/reproduce.py
```

At the current commit the script prints the leaked-generator warnings for the
trio runner of each scenario and exits 1. Once the tree is repaired it must
exit 0 with no leaks under either runner.

## What to do

1. **Reproduce**: run `/app/reproduce.py` and read what it reports. The three
   scenarios are a plain `{% for %}` stream, a template that `{% include %}`s
   with context, and a template that `{% extends %}`s a parent.
2. **Localise**: the cause lives in the library source under `/app/src/src/`.
   The project's own test suite is the fast, targeted way to explore the
   async machinery — it is tiny and runs in a few seconds:

   ```bash
   cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest -q tests/ -p no:cacheprovider
   ```

   (Note: `pyproject.toml` turns warnings into errors for pytest, so any
   test that leaks an async generator fails loudly.) The whole suite passes
   at the current commit, because the regression predates this commit's own
   tests: it is a real, subtle oversight that upstream did not have coverage
   for at this point in history. Use the reproducer and your own small
   scripts to probe the streaming paths — `Template.generate_async` and its
   interaction with compiled template code that yields from nested
   generators (parent/child templates, includes, block calls).
3. **Fix the root cause in the library source.** Do not modify any test
   file, do not add post-processing, wrappers, monkey-patching or a
   catch-warnings filter that hides the diagnostic. The repair must make the
   generators actually get closed, so that nothing leaks. Repair it at its
   source, in the tree.
4. **Prove it**: `/app/reproduce.py` exits 0, and the project's own suite
   still passes in full:

   ```bash
   cd /app/src && PYTHONPATH=/app/src/src python3 -m pytest -q tests/ -p no:cacheprovider
   ```

   Everything must stay green after your change.

## Deliverables

1. The repaired source tree **in place under `/app/src`** (ordinary file
   edits). Every file that your fix does not genuinely need to change must
   remain byte-identical to what was there, and you must not add or remove
   files in the tree.
2. `/app/diagnosis.md` — a short root-cause note (a few sentences minimum)
   stating, in your own words:
   - **the area**: which part(s) of the engine are involved,
   - **the root cause**: what the code did wrong and why the problem only
     shows up under strict runtimes,
   - **the fix**: the minimal change you applied.

Both are checked.

## Constraints

- Do not modify `/app/reproduce.py` or any file under `/tests` (you cannot
  see the latter anyway). Do not touch `pyproject.toml` or any test file —
  the tree is byte-audited: any modification outside the library source that
  the fix actually requires fails the task even if the tests pass.
- No network: the trial runs fully offline.
- The time budget is generous; the expensive part is finding the bug, not
  running the checks.