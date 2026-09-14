# companion-flint

You are working inside a real open-source codebase: **mypy** (the static type
checker for Python, `python/mypy`), checked out at a pinned historical commit
in `/app/src` (the working tree starts clean and detached). There is a bug in
this tree's handling of **default argument values**. Your job is to find it,
fix it in the working tree, and prove the fix with the project's own test
tooling. You are deliberately **not** told which file or function to change:
localising the bug is part of the task.

## Environment

- mypy runs straight from this source tree: from inside `/app/src`,
  `python3 -m mypy <file>...` imports and executes *this tree's* code. mypy
  itself is not pip-installed anywhere; the Python packages mypy needs at
  runtime and for its test suite are installed system-wide, pinned to the
  exact versions the project's own CI used at this commit (pytest 8.4.2,
  pytest-xdist 3.8.0, lxml 6.0.2, typing-extensions 4.15.0,
  mypy-extensions 1.1.0, pathspec 1.0.0, librt 0.10.0, ast-serialize 0.3.0,
  attrs 25.4.0).
- The tree lives at `/app/src` and is writable by you, but **do not commit,
  fetch, push, rebase or otherwise modify `.git`** — the working tree is
  detached at the pinned commit and must stay there. No commits, no grafted
  history.
- **There is no network** in this container. Nothing can be pip-installed and
  nothing can be cloned or fetched. Everything needed is already here.
- `cpus = 1`: a single vCPU. A mypy run on one file takes ~2s; the project's
  data-driven tests take a few seconds per filter.
- The project's own test suite is data-driven: cases live in
  `test-data/unit/check-*.test` files and run with
  `python3 -m pytest mypy/test/testcheck.py -k <selector> -n 1`.
  The project configures pytest-xdist (`-n auto`); pass `-n 1` explicitly to
  keep it deterministic on this one-CPU container. The tests are fully
  offline.
- `PYTHONPYCACHEPREFIX=/tmp/pycache` is set, so Python bytecode caches never
  land inside the tree.

## The bug (user-visible symptom)

Python lets you declare a type variable with an explicit list of allowed value
types, e.g. a variable whose values may only be `B` and `C`, where `C` is a
subclass of `B`. A parameter annotated with such a type variable may carry a
default value. The default only has to be valid *for the parameter*, i.e. its
type must be one of the allowed value types (or, more generally, a subtype of
all of them). So a default whose type is the subclass case above is legal and
must type-check cleanly.

On this tree, mypy gets this wrong. It reports a default that is a proper
subtype of every allowed value type (in particular, a default that is itself
one of the declared value types) as incompatible with the parameter, emitting
the `Incompatible default for parameter` diagnostic even though the default is
legally permitted by the type variable's value list.

A default that is genuinely invalid — its type is *not* a subtype of every
allowed value type, such as an instance of the superclass in the example above
(because it is a supertype of the subclass) — must still be reported exactly as
it is today.

The affected behaviour is the default-value check for parameters annotated
with a value-restricted type variable: legal defaults must be accepted;
illegal ones must still be rejected.

## Your job

1. **Write a failing reproduction first.** Before you change any source
   code, write `/app/repro.py` — your own minimal reproduction of the
   symptom:

   - a single Python file, plain typing-only code (no `# flags:` comments,
     no `# type:` comments, no `typing` games beyond the declaration itself);
   - it must declare a type variable with a value list, a class hierarchy in
     which one of the listed value types is a proper subtype of all the
     others, and a function whose parameter is annotated with that type
     variable and has a **legal** default value of that subtype — exactly the
     input shape that trips the bug;
   - it must contain **no code that is genuinely invalid** (no illegal
     defaults, no name errors, no syntax errors, nothing that any correct
     type checker could reasonably reject): on a correct mypy this file
     type-checks with exit code 0 and no diagnostics.

   Write `/app/repro.sh`, a runner that honours an environment variable
   `MYPY_DIR` naming the mypy tree to use (default `/app/src` when unset) and
   does exactly this, from any working directory:

   ```bash
   (cd "$MYPY_DIR" && python3 -m mypy --no-incremental --cache-dir=/tmp/myrepocache /app/repro.py)
   ```

   It must print everything mypy prints (stdout and stderr) and nothing else,
   and exit 0 if and only if mypy exits 0 and printed no `error:` diagnostics
   (mypy's normal success line, "Success: no issues found in ...", is fine).

   On the **unfixed** tree this must fail: mypy exits non-zero and prints the
   `Incompatible default for parameter "x"` diagnostic for your legal
   default. Confirm that now, before fixing anything.
2. **Fix the tree.** Make the smallest possible change so that
   `/app/repro.py` type-checks cleanly (exit 0, no diagnostics). Fix the
   mechanism, not just one input: the same defect is reachable with any
   number of value types, with defaults whose type is a subtype of every
   value type without being one of the listed types, and with keyword-only
   parameters (see Grading). Do not special-case your reproduction in a
   wrapper script — the graded checks exercise the code path directly through
   `python3 -m mypy` on both the repaired tree and a pristine pre-fix tree.

3. **Break nothing else.** Everything else must keep working exactly as
   before: value-restricted type variables in call positions and argument
   checks, `isinstance` narrowing, generic function bodies, and the rest of
   the type-variable semantics. The project's own type-variable tests must
   stay green.

4. **The graded tree must be byte-identical to the pinned commit except for
   the single source file where the bug lives.** Do not add, move, delete,
   rename or reformat any file; if you create scratch files to investigate
   (including mypy caches — prefer `/tmp` for those), delete them before you
   finish; make no commits; do not modify tests or test data. The grader
   compares every file's bytes against the pinned commit's own blobs, so
   cosmetic side-changes also fail. Your authored files `/app/repro.py`,
   `/app/repro.sh` and `/app/summary.md` live **outside** `/app/src` and are
   fine.

5. **Write `/app/summary.md`** — a non-empty write-up: what the bug was,
   what you changed, and how you verified it.

## Working loop (recommended)

1. **Reproduce** with `/app/src` exactly as described: write a minimal legal
   default-argument program, run mypy on it, observe the false rejection.
   Experiment with variants (value lists of different lengths and orders,
   defaults that are subclasses of several value types, keyword-only
   parameters, genuinely invalid defaults) to pin down precisely which input
   shapes are wrongly rejected and which are correctly rejected.
2. **Localise** the bug by reading the code. Trace where a parameter's
   default value is checked against its declared type, then where the
   subtype decision involving the value-restricted type variable is made.
   Understand why a default that is a subtype of every allowed value type is
   rejected, and where the missing special case belongs.
3. **Fix** with the smallest possible change, then rerun `/app/repro.sh`
   (must pass) and the data tests.
4. **Prove nothing else broke**: run the project's type-variable data tests,
   for example
   `python3 -m pytest mypy/test/testcheck.py -k "check-typevar" -n 1 -q`
   (a few seconds; it covers `check-typevar-values`,
   `check-typevar-defaults`, `check-typevar-tuple` and
   `check-typevar-unbound`). All must pass.
5. Write `/app/summary.md`.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree.
2. `/app/repro.py` — your own minimal reproduction (single legal-default
   file), per the contract above.
3. `/app/repro.sh` — the runner honouring `MYPY_DIR`, per the contract
   above.
4. `/app/summary.md` — the write-up.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, that the upstream
  fix commit is **not** reachable from this clone, and that every tracked
  file except the single source file the bug lives in is byte-identical to
  that commit (any other modification, added file or untracked scratch file
  fails);
- require `/app/repro.py`, `/app/repro.sh` and `/app/summary.md` to exist,
  be non-empty and behave per their contracts;
- run your `/app/repro.py` through the repaired tree's mypy directly (it
  must type-check cleanly, exit 0, no diagnostics) **and** through a
  pristine pre-fix tree baked into the image at `/opt/mypy-parent` (it must
  fail with the `Incompatible default for parameter` diagnostic — proving
  the symptom is real and your reproduction targets it), and also execute
  your `/app/repro.sh` in several directions: via the default `MYPY_DIR` and
  via throwaway copies of the repaired and pre-fix trees at paths you cannot
  pre-know (so the runner must actually run mypy from whatever tree
  `MYPY_DIR` names, printing mypy's real success line or diagnostic
  through);
- plant the project's **own regression test** for this bug (baked into the
  image at `/opt/golden` — upstream added it together with the fix, so it
  does not exist in this tree) into the type-variable data file, run it, and
  require it to pass;
- require the full existing type-variable data sweep
  (`-k "check-typevar"`: all four `check-typevar-*.test` files, 219
  existing cases) to pass on your repaired tree, proving the fix broke
  nothing else;
- add several authored hidden cases exercising the same code path from
  inputs the upstream regression test does not use — a value list with three
  levels, a default that is a subtype of every value type without being one
  of the listed types (multiple inheritance), and a signature with several
  parameters including keyword-only ones — and requires each to pass on your
  repaired tree **and** to fail on the pristine pre-fix tree, so passing the
  upstream test alone is insufficient.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.