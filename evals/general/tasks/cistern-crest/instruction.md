# Files with no usable date must not inherit another file's mtime

## Situation

`/app/src` is a shallow, pinned clone of the gallery-dl project
(`https://github.com/mikf/gallery-dl`), checked out at upstream commit
`a879e5d468e43fac9daf6bdc4726f853a9c85567`, and installed from that tree in
editable (development) mode, so the code you import is exactly the checked-out
Python source. Python 3.12 and pytest are installed. There is **no network**
at trial time: everything you need is already in the image; `pip` and
`git fetch` will not work.

## The bug

gallery-dl has an `--mtime` postprocessor: when enabled, each downloaded
file's modification time is set from that file's metadata (by default from its
`date` field). The postprocessor records a Unix timestamp in the metadata
under `_mtime_meta`, and the downloader applies it to the finished file.

In this checkout the postprocessor mishandles files whose metadata carries no
usable date. When a run downloads several files with a date-based `--mtime`
value:

- a file whose metadata has **no date at all** ends up with the **previous
  file's** modification time -- the timestamp from one file sticks to the
  next, so a single run can stamp several files with the identical wrong
  time;
- metadata that contains an **invalid / unparseable / "no date"** date value
  is treated as a real date, producing an absurd modification time in the year
  0001 (a huge negative timestamp gets applied to the file).

Files with a missing or invalid date should simply not be stamped: no
timestamp inherited from a previous file, and no garbage timestamp. Files
with a valid date must keep being stamped exactly as before (`01 Jan 1980
00:00:00 UTC` must still map to the timestamp `315532800`).

## Reproducing the failure

```
python3 /app/probe_mtime.py
```

simulates one job writing three files whose metadata dict is shared, and
prints the recorded `_mtime_meta` after each file. In this checkout:

- the second file (no date metadata) prints the *first* file's timestamp
  instead of `None` -- the leak;
- the third file (invalid date sentinel) prints a huge negative timestamp
  (year 0001) instead of `None`.

## What you need to do

Fix the bug in the checked-out tree at `/app/src`. Valid dates must keep
producing exactly the same timestamps as today; missing, empty, invalid and
"no date" values must not leak a previous file's timestamp onto the next file
and must not produce garbage timestamps.

Drive your work with the project's own test runner and the probe:

```
cd /app/src && python3 -m pytest test/test_postprocessor.py -k 'not mtime' -q -p no:cacheprovider
cd /app && python3 probe_mtime.py
```

The project's own postprocessor test file is green for everything except the
mtime tests, two of which assert the buggy behaviour itself (that no metadata
record is produced at all when a file has no date). A correct fix makes those
two in-tree assertions outdated; the verifier relies on the project's own
regression tests for the corrected behaviour plus its own hidden checks, not
on those stale expectations. Add your own tests if that helps you verify (for
example an end-to-end sequence of several files through the shared metadata
dict), but the verdict is made by the verifier.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add or fetch remotes, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not
  touch them.
- The verifier also asserts that the working tree is still at the pinned
  commit, that no other tracked file was modified, and that no new files were
  added inside the gallery_dl package.

## What the verifier checks

1. The tree is still at commit `a879e5d468e43fac9daf6bdc4726f853a9c85567`,
   the fix is not reachable from the working clone (no fetching), and the
   repair touches only the minimal source surface.
2. The project's upstream regression tests for the corrected behaviour
   (extracted from the project's own test history at image build time) pass.
3. The project's own existing postprocessor tests still pass (excluding the
   mtime tests, whose expectations encode the bug), proving the fix broke
   nothing else.
4. Hidden cases over inputs the upstream tests do not use pass: a
   several-files-one-job sequence where no stale timestamp may leak across
   files, and the `value` / `key` option paths with missing, empty and
   invalid inputs.

Deliverable: the repaired `/app/src` tree.