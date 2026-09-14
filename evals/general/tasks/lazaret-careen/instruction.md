# lazaret-careen

You are working inside a real open-source codebase: **NetworkX**
(`networkx/networkx`), the Python graph-analysis library, checked out at a
pinned commit in `/app/src` (working tree clean). There is a bug in the GML
reader/writer: for some programs that write a graph to the GML text format
and read it back, the graph that comes back is **not the graph that was
written**. Your job is to find the bug, fix it in the working tree, and
prove the fix with the project's own test tooling.

You are deliberately **not** told which file or line to change: localising
the bug is part of the task.

## Environment

- Python 3.12.13 with `pytest 9.1.1`. The repository is installed editable
  (`pip install -e /app/src`), so `import networkx` resolves to the tree at
  `/app/src`. Do not reinstall or uninstall anything.
- **There is no network** in this container. Everything you need is already
  on disk, including `pytest`.
- `cpus = 1`: one vCPU.
- `/app/src` is a shallow clone (one commit, detached HEAD). Do not commit,
  fetch, or otherwise modify `.git`. The tree must end up byte-identical to
  the pinned commit except for the **single source file where the bug
  lives**; do not add, move, delete, rename or reformat any other file, and
  delete any scratch files you created inside the repository before you
  finish.

## The bug (user-visible symptom)

The GML format stores attribute values — including the `label` of a node —
as quoted strings. NetworkX can write a node whose label is a **tuple**,
e.g. a 2D coordinate `(12.5, -3.25)`; it renders the tuple as a quoted
string that looks exactly like the tuple's `repr()`.

For most labels everything round-trips fine. But there is a class of
labels for which writing the graph produces output that is **invalid and
unsafe**: when the tuple's string form contains a **double-quote character
(`"`)**, that quote is written into the GML file **raw, without any
escaping** — even though quotes inside ordinary string labels are escaped
into the entity `&#34;` so the format stays well-formed.

Because the raw quote is a real GML quote, it closes the label string
early. Everything in the label text after that quote is then interpreted by
the reader as structure — so a crafted label can **inject extra nodes and
attributes** into the file, and even an accidental quote (for example in a
file name `report "final" 2026.xlsx` inside a tuple) makes the round-trip
silently produce a **different, larger graph** than the one that was
written, or fail to parse at all.

Concretely: on the current tree, writing a 1-node graph whose tuple label
contains such a quote produces GML text with the raw quote in it, and
reading that text back yields a graph that is not the one that was written —
extra nodes/edges appear (or the read fails outright). Demonstrate it
yourself in your reproduction: build a tuple-typed node label whose
`repr()` contains a double-quote character, write a graph containing that
node to GML text (`generate_gml`), and inspect both the emitted text and
the round-trip. Try a few label shapes — the quote in the first element,
in a later element, and in a tuple that also holds a non-string element —
until you have a label that corrupts the round-trip.

Tuple node labels must be escaped exactly like plain string labels, so the
written GML is well-formed and reading the file back always returns exactly
the graph that was written, for **any** tuple label content.

## Requirements

1. **Write your reproduction first — before you change any code.** Create
   `/app/reproduce.py`, a standalone Python script (stdlib + `networkx`
   only, no other third-party imports) that demonstrates the bug: it must
   exit **non-zero** (for example via `assert`) when run against the
   current tree, and exit **0** once the tree is correctly fixed. A good
   reproduction checks both the generated text (the raw quote must be gone,
   the `&#34;` entity present) **and** the round-trip (parsing the generated
   GML must yield exactly the single node that was written, with the label
   text intact). `/app/reproduce.py` is executed from an arbitrary working
   directory, against whichever tree is under test, so it must not depend
   on the current directory for imports or for files it writes — put any
   scratch data only in the system temp directory (`tempfile`).
2. Fix the tree at `/app/src` so the symptom is gone: GML written by the
   project must escape double quotes in tuple labels like it already does
   for ordinary string labels, and `write_gml`/`parse_gml`/`read_gml` must
   round-trip **any** tuple label to the graph that was written. Fix the
   root cause — do not special-case the strings in the example, and do not
   change the way **non-label** list/tuple values are written; the project
   has tests pinning that behaviour.
3. Keep everything else working. The project's own GML tests (under
   `networkx/readwrite/tests/`) pass on the pristine tree and must keep
   passing after your fix:
   `python -m pytest networkx/readwrite/tests/test_gml.py -q`
   The grader additionally plants **the regression test the project's
   maintainers added for this exact bug** (baked read-only into the image;
   it is not in your tree yet) into the project's own test module and runs
   the whole `networkx/readwrite/tests/` directory, so do not modify any
   test file.
4. Deliverables, all three:
   - `/app/src` — the repository with your fix applied in the working tree
     (the only differing file must be the one the bug lives in);
   - `/app/reproduce.py` — your reproduction from step 1, finished;
   - `/app/summary.md` — a non-empty write-up: what the bug was, what you
     changed, and how you verified it (include what your reproduction
     printed before and after the fix).

## Working loop (recommended)

1. **Reproduce.** Write `/app/reproduce.py` following the requirements
   above, run it against the current tree (`python3 /app/reproduce.py`) and
   confirm it exits non-zero, demonstrating the corruption. Keep scratch
   files in `/tmp`, never inside `/app/src`.
2. **Localise.** Read the GML writer carefully and find where tuple labels
   are turned into quoted strings and where ordinary string labels get
   their escaping, and understand why the two paths differ.
3. **Fix** with the smallest possible change. Re-run your reproduction: it
   must now exit 0. Then run the project's own GML tests as above; they
   must stay green.
4. **Probe your fix** with other tuple labels of your own before finishing
   — quotes in different positions, several elements, non-string elements,
   labels whose text also contains backslashes — and confirm every one
   round-trips to the single node that was written and that no raw quote
   from any label ever leaks into the GML text.
5. Write `/app/summary.md`.

## Grading

The verifier (the container's own `/tests`) will, on your final tree:

- assert that `HEAD` is still the pinned parent commit, and that every
  tracked file except the single source file the bug lives in is
  byte-identical to that commit (any other modification, added file or
  untracked scratch file fails);
- require `/app/summary.md` to exist and be non-empty;
- run **your** `/app/reproduce.py` against a pristine pre-fix snapshot of
  the same commit — it must FAIL there (a reproduction that cannot fail is
  not a reproduction) — and again against your repaired tree, where it must
  PASS;
- plant the upstream regression test for this bug and run the whole
  `networkx/readwrite/tests/` directory — the regression test must pass
  and the project's other tests must stay green;
- run **hidden cases**: other crafted tuple labels that reach the same
  escaping path from inputs the upstream test does not use (a 3-tuple with
  the injection in a later element, an injection verified through the file
  API `write_gml`/`read_gml`, and a mixed-type label containing both a
  backslash and a quote). Each must round-trip as exactly the one node that
  was written, with no raw quote in the emitted text.

Reward is binary: 1 if and only if all of the above hold, otherwise 0.