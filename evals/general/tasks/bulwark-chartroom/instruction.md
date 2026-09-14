# The reported mount path of your app is mojibake

## Situation

`/app/src` is a shallow, pinned clone of the **Falcon** web framework
(`https://github.com/falconry/falcon`), checked out at a specific upstream
commit that still contains the bug, and installed from that tree in editable
(development) mode, so the code you import is exactly the checked-out Python
source. Python 3.12, pip, git and pytest are installed. There is **no
network**: everything you need is already in the image; `pip install` and
`git fetch` will not work against the internet.

The tree is a detached single-commit worktree: its object store holds exactly
the pinned commit and nothing else. Do not commit, create branches or tags,
add remotes, fetch, or rewrite anything. All of your work happens under
`/app`; scratch material goes under `/tmp`. Files under `/opt` (the verifier's
own pre-baked trees), `/tests` and `/solution` are harness-owned — do not
touch them.

This is a real, unfamiliar codebase (a few hundred Python source files under
`falcon/`). Localising the bug is part of the task: you are deliberately **not
told which file, function or environment variable to change**, and the fix is
**not** to be applied anywhere other than the checked-out tree at `/app/src`.

## The bug, as a user reported it

> “We mount our WSGI application under a URL prefix that contains a
> non-ASCII letter (the deployment platform mounts every app under a path
> based on its name, and some of ours have accents). Since the last upgrade,
> whatever the framework reports as the application's *root path* — the mount
> prefix — shows a garbled double-encoding instead of the correct spelling:
> the prefix `/café` comes back reported as `'/cafÃ©'` (the accented `é`
> shows up as the two Latin-1 glyphs `Ã©`). URLs the framework reconstructs
> with that prefix come out wrong, and routing decisions that look at the
> prefix break. An ASCII prefix like `/api` is reported correctly.”

The affected behaviour, precisely:

- `Request.root_path` — the reported location/mount prefix of the app under a
  WSGI (PEP 3333) deployment — must be returned as the correct, properly
  decoded Unicode string, exactly matching the original spelled prefix.
- Today it is not: when the mount prefix contains any non-ASCII character,
  the reported `root_path` is the mojibake (latin-1 double-shot) form of the
  prefix, and every URL built from `root_path` (and every route comparison
  that uses it) inherits the corruption.

## Your job

1. **Write your failing reproduction first.** Before changing any source
   code, create `/app/repro.py` — a standalone Python 3 script that
   reproduces the symptom above through Falcon's own machinery. Its contract:

   - No command-line arguments, no network, no files other than the installed
     `falcon` package and the Python standard library.
   - It must construct its own WSGI request environ (for example with
     `falcon.testing.create_environ()`), with the WSGI environ's
     `SCRIPT_NAME` entry (the mount prefix, as a real PEP 3333 WSGI server
     hands it to the application) set to a non-ASCII mount prefix — use a
     prefix containing at least one character outside ASCII, e.g. an accented
     letter.
   - It builds `falcon.Request` from that environ and reads the reported root
     path.
   - Output contract: exactly one line whose text starts with
     `observed root_path:` followed by the `repr()` of the reported value.
   - Exit contract: exit code **0** if and only if the reported root path is
     the correct, correctly-decoded Unicode spelling of the prefix; otherwise
     print a line starting with `BUG:` and exit with a non-zero code.

   Confirm **now**, before touching any source, that on this tree
   `python3 /app/repro.py` fails exactly as the report describes (mojibake
   value, non-zero exit). After your fix the same command must pass unchanged.

2. **Fix the tree.** Make the change, in `/app/src`, so that the reported
   root path is the correctly-decoded Unicode prefix for any non-ASCII mount
   prefix — not just for the one accent you test. The same defect is
   reachable with prefixes in other scripts (Cyrillic, fullwidth, emoji) and
   with non-ASCII byte sequences that do not form valid UTF-8; the grader
   exercises those, and expects sane behaviour (a safe substitution) rather
   than a crash or a raw glyph dump. Fix the mechanism, not one input: do not
   hardcode any particular prefix, do not hide the symptom, do not special-case
   the tests.

3. **Break nothing else.** The project's own test suite is green at the
   pinned commit (3786 tests). Keep it green. Drive your work with the
   project's own runner:

   ```
   cd /app/src && python3 -m pytest tests/ -q -p no:cacheprovider
   ```

   Add your own tests (for example in a scratch file under `/tmp`) if that
   helps you verify.

## Constraints

- The working tree must remain at the pinned commit: no commits, no fetches,
  no branch/tag manipulation.
- Repair the bug by changing the minimal amount of tracked source. The
  verifier rejects trees where tracked files other than the single
  framework source file that owns this behaviour were modified, and rejects
  new files added inside the `falcon/` package or the `tests/` directory
  (your reproduction lives at `/app/repro.py`, outside the repository).
- Do not touch anything under `/opt`, `/tests`, `/solution`, `/usr`, or
  `/etc`. Do not rely on the network.

## Deliverables

1. `/app/src` — the repository with your fix applied in the working tree
   (uncommitted changes are expected and sufficient).
2. `/app/repro.py` — your reproduction, per the contract above.

## Grading

The verifier runs after you finish, against your final tree, and asserts,
among other checks:

- provenance: the tree is still at the pinned commit, the upstream fix commit
  is not reachable from the working clone, the only modified tracked file is
  the framework source file that owns this behaviour, and no new files
  appeared inside the `falcon/` package or `tests/`;
- your `/app/repro.py` **passes** against `/app/src` (exit 0, observed value
  correct) and **fails** (non-zero exit, observed value printed) against a
  pristine, unmodified pre-fix copy of the tree the verifier keeps at
  `/opt/prefix-src`;
- the project's own regression test for this bug — added upstream in the
  commit that fixed it, so it is not present in your tree — passes when run
  against your tree, and fails against the pristine pre-fix copy;
- the project's own full test suite passes on your tree, and additional
  hidden cases exercising the same behaviour from inputs you have not seen
  pass as well.

Reward is binary: 1 if and only if every check above passes on your tree,
otherwise 0.