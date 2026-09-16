# bandit logs an internal error on a Django raw-SQL call and never reports it

## The situation

`/app/src` is a shallow, pinned clone of **bandit** (`https://github.com/PyCQA/bandit`),
a security-oriented static analyzer for Python, checked out at upstream commit
`6d6ec6d550ef3ce1c7b6b04a56931bac65e94f71` and installed from that tree in
editable (development) mode, so the `bandit` command-line tool and
`python3 -m bandit` execute exactly the checked-out source. Git, Python 3.12,
pip, pytest, stestr and the packages the project's own test configuration needs
are installed. There is **no network** at trial time: `pip` and `git fetch`
will not work; everything you need is already in the image.

## The symptom

A user scanning Django code with bandit sometimes sees, mixed into the scan
output, an alarming line like

```
[main]	ERROR	Bandit internal error running: django_rawsql_used on file ./dbview.py at line 3: list index out of range
```

followed by a Python traceback whose last frame is
`IndexError: list index out of range`. The scan does not abort: bandit logs the
internal error to stderr, keeps going, and exits with the same status and the
same issue metrics as if nothing had gone wrong — which is exactly why it is so
easy for a user to miss.

The affected behaviour: `django_rawsql_used` is the analyzer that flags risky
use of Django's raw-SQL expression helper (the ORM's non-parameterized query
constructor). When a vulnerable raw-SQL call is written **one particular valid
way**, the analyzer dies internally instead of reporting the call, so the scan
shows **no finding at all** for a call that should be reported as a SQL
injection risk. Written the usual way, the same call is detected fine.

Note the crash only ever fires on files that import Django's model layer
(`django.db.models` or one of its submodules, e.g. `django.db.models.expressions`) —
bandit inspects that import to decide the rule applies. The scanned file does
not need Django installed or runnable: bandit scans statically and Django is
not in the image, so the trigger file just needs the import statement plus the
call.

## What you need to do

1. **Before changing anything**, find the valid calling pattern that provokes
   the internal error, and write your own failing reproduction as the
   deliverable `/app/repro.py` (contract below). Run it: while the bug is
   present it must fail.
2. Repair the analyzer in `/app/src` so that scanning the same input produces
   no internal error — the `Bandit internal error` log line must never appear
   for that input — **and** the risky raw-SQL call is reported as a finding
   again (the `django_rawsql_used` rule, severity Medium). Every other scan
   behaviour must be unchanged: positional calls, unaffected calls and normal
   code must behave exactly as they did before your repair.
3. Drive your work with the project's own test runner, from `/app/src`:

```
python3 -m stestr run --concurrency 1
```

   The whole project test suite (267 tests) is green at the pinned commit;
   keep it that way. You may add your own tests or sample files anywhere under
   `/app` if that helps you verify, but the verdict is made by the verifier,
   which checks things its own way.

## Deliverable contract — `/app/repro.py`

A self-contained reproduction. It must:

- take no arguments and work from any current working directory (it must not
  depend on being invoked from a particular directory);
- create its own small Python source file that triggers the internal error
  (for example with a temporary file), scan it with the installed bandit
  itself (spawn it as a subprocess with `sys.executable -m bandit <file>`),
  and print everything bandit wrote to stdout and stderr (bandit's diagnostics
  go to stderr);
- exit `0` if and only if the scan completed with no line containing
  `Bandit internal error` on bandit's stderr, and a non-zero status otherwise.

The verifier runs exactly this script twice: (a) against the repaired tree,
where it must exit `0` **and** its scan output must contain the raw-SQL
finding for the risky call (`B611`, `Use of RawSQL potential SQL attack
vector`) — that is what proves the reproduction genuinely exercises the
vulnerable behaviour instead of passing vacuously; and (b) with the pristine
pre-fix tree from `/opt/pretree` on the import path, where it must exit
non-zero **and** print the internal-error evidence — that is how the verifier
proves your reproduction fails while the bug is present.

## Constraints

- Network is unavailable; everything needed is installed already.
- The repaired clone is a deliverable. Change only what the fix requires, in
  place. The verifier asserts: HEAD is still the pinned commit; the working
  clone contains exactly one commit (nothing was fetched, no history was
  added); no tracked file was deleted; no new files were added under `bandit/`;
  and the only modified tracked files are source files under `bandit/` (at
  least one such modification is present). In particular, do not edit anything
  under `tests/` or `examples/`, do not change build or install files, and do
  not add import-time wrappers such as `sitecustomize.py`/`usercustomize.py`:
  the fix must live in the checked-out source itself.
- Files under `/opt/pretree`, `/tests` and `/solution` are harness-owned; do
  not touch them, and do not expect them to contain anything useful to you.
  `/opt/pretree` is a second copy of the same pre-fix tree the verifier uses
  for its two-tree comparisons; `/tests` and `/solution` are not present
  during your session.
- `import bandit` must still resolve to the checked-out tree at `/app/src` (it
  does; do not reinstall, uninstall or move anything, and do not create a
  second bandit package anywhere else on the import path).

## What the verifier checks

1. Provenance: the tree is still at commit
   `6d6ec6d550ef3ce1c7b6b04a56931bac65e94f71`, the working clone contains no
   other history, no tracked file was deleted, only source files under
   `bandit/` are modified (at least one), `import bandit` resolves to
   `/app/src/bandit`, and the unguarded indexing that crashes the analyzer is
   gone from the source with a guard in its place — the fix must be in the
   code, not in a wrapper.
2. Your `/app/repro.py`: it must exit `0` and report the raw-SQL finding
   against the repaired tree, and it must exit non-zero while printing the
   `internal error` evidence against the pristine pre-fix tree at
   `/opt/pretree`.
3. The upstream regression material for this behaviour passes: the verifier
   reconstructs the fix-commit revision of the project's functional test and
   its example from the pristine pre-fix tree's own files and runs it, so the
   judgement uses the project's own test machinery.
4. The project's own test suite (267 tests) still passes.
5. Hidden cases over trigger shapes the upstream material does not use pass on
   the repaired tree, and the verifier's own scans of those shapes show **no**
   `internal error` on the repaired tree — while the pristine pre-fix tree
   still shows the `internal error` on exactly those shapes, proving the
   repairs removed the crash and not merely papered over this one scan.

Deliverables: the repaired `/app/src` tree and `/app/repro.py`.