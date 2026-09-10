# The defect in sympy's discrete transforms

This is a clean-room debugging task against a real upstream codebase, in the
SWE-bench style: you are handed a genuine regression in a library you did not
write, a failing behaviour, and a reproducer -- but not the file, the function,
or the line that is wrong. You have to localise the defect, fix it so that the
library's own test suite for the affected area passes again, and write a short
diagnosis.

## Environment

- `/app/src` is a working copy of the real SymPy 1.14.0 tree (shallow clone,
  exactly commit `16fa855354eb7bcabd3fe10993841e03b1382692`), Python 3.12
  compatible. The tree is complete and editable, but it has **no git history**
  and there is **no network** in this container: you cannot re-fetch anything,
  so do not delete or regenerate the tree, and do not try to `pip install`
  anything new.
- Python 3.12.13 with the packages SymPy needs for its own test suite
  (mpmath, pytest, hypothesis) installed.
- To run Python against this tree use
  `cd /app/src && PYTHONPATH=/app/src python3 ...` or just edit the tree and
  run the commands below from `/app/src`.

## The failing behaviour

In one of SymPy's modules for discrete signal processing, one routine returns
**numerically wrong results whenever its input has 8 or more samples**.
Short inputs (length 1, 2 or 4) still produce correct values, which is why the
regression went unnoticed by quickly-written examples.

Run the reproducer, which compares SymPy's routine against an independent
naive implementation and reports which checks pass and which fail:

```bash
cd /app/src && python3 /app/reproduce.py
```

It exits 0 once the tree is fixed and non-zero while the defect is present.

## What to do

1. Observe the failing behaviour with `/app/reproduce.py`.
2. Localise the defect. The code lives somewhere under `/app/src/sympy/`; the
   affected submodule's own test suite is the fast, targeted way to pinpoint
   it -- run only that submodule's tests, never the whole SymPy suite (that
   would take far too long at one CPU):

   ```bash
   cd /app/src && PYTHONPATH=/app/src python3 -m pytest -q sympy/discrete/
   ```

   This takes about two seconds. Failures will name the routines involved.
3. Fix the cause in the library source. Do **not** modify any test files,
   do **not** add post-processing or a wrapper that papers over the wrong
   output, and do **not** special-case particular input lengths. The root
   cause is a single small defect; repair it at its source.
4. Re-run `/app/reproduce.py` and the submodule's whole test suite (every
   test in `sympy/discrete/tests/` must pass again) to prove the fix.

## Deliverables

1. The repaired source tree in `/app/src` (your fix, committed to disk as
   ordinary file edits).
2. `/app/diagnosis.md` -- a short root-cause note (at least a few sentences)
   that states, in your own words:
   - **the module**: the SymPy package/module where the defect lives,
   - **the root cause**: what the code did wrong and why short inputs
     escaped it,
   - **the fix**: the minimal change you applied.

Both deliverables are checked. If `/app/diagnosis.md` is missing or does not
identify the actual module and cause, the task fails even if the tests pass.

## Constraints

- Do not modify `/app/reproduce.py` or any file under `/tests` (you cannot
  see them anyway).
- Do not remove or rewrite the test suite of the affected submodule.
- No network: the trial runs fully offline. Everything you need is already
  in the image.
- Time budget is generous; the expensive part is finding the defect, not
  running the checks.