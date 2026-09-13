# Note-name tuning deviations are silently discarded by note-to-frequency conversion

## Situation

`/app/src` is a shallow, pinned clone of the librosa repository
(`https://github.com/librosa/librosa`), checked out in detached HEAD at an
upstream revision that has the behaviour described below. The
project is already installed from that checkout in editable mode, so
`import librosa` resolves to `/app/src/librosa` and any edit you make under
`/app/src/librosa` is live immediately — no reinstall, no compilation. librosa
is pure Python plus numba; there is nothing to build.

There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail.

The project keeps its unit tests under `/app/src/tests` and runs them with
pytest. One environment quirk you will hit: on this image a plain
`python3 -m pytest tests/test_convert.py` fails test collection with
`No librosa.core attribute convert` before running anything. That is a
lazy-import timing issue in the installed `lazy_loader` version (the test
module reads `librosa.core.convert.WEIGHTING_FUNCTIONS` at import time), not
your problem to fix. Work around it by running pytest through a tiny wrapper
that pre-imports the submodule inside the same interpreter:

```
cd /app/src && python3 -c "import sys, librosa.core.convert, pytest; sys.exit(pytest.main(list(sys.argv[1:])))" tests/test_convert.py -o addopts= -p no:cacheprovider -q
```

## The bug

librosa converts spelled note names to frequencies with
`librosa.note_to_hz(...)`. A note name may carry a tuning deviation, written
as a cents suffix, for example `'C2-30'` (the note C2 detuned 30 cents flat)
or `'A4+50'` (A4 detuned 50 cents sharp).

Passing a note name that carries such a deviation to the note-to-frequency
conversion returns exactly the same frequency as the plain note name with no
deviation, as if the cents suffix were ignored entirely. Concretely, right
now:

```
python3 -c "import librosa; print(repr(librosa.note_to_hz('C2-30')), repr(librosa.note_to_hz('C2')))"
```

prints the same number twice: `65.40639132514966 65.40639132514966`. The
`-30` cents tuning deviation is silently discarded, with no error or warning,
so anyone converting detuned or microtonal note spellings gets a frequency
that only ever lands on the nearest equal-tempered semitone — the unit tests
above do not catch it, because they pass the rounding option explicitly to
both conversions.

## What to do

Fix the conversion so that a note name with a cents tuning deviation is
converted to its detuned frequency **by default**. The deliverable is the
repository at `/app/src`: modify the code there until the behaviour below
holds, in the full suite run, `import librosa` resolves to `/app/src/librosa`.

The intended behaviour:

- `librosa.note_to_hz('C2-30')` must **differ** from
  `librosa.note_to_hz('C2')`, and must equal
  `librosa.note_to_hz('C2-30', round_midi=False)`.
- `librosa.note_to_hz('A4-50')` must equal `440.0 * 2.0 ** (-50 / 1200)`
  (≈ 427.47 Hz) and `librosa.note_to_hz('A4+50')` must equal
  `440.0 * 2.0 ** (50 / 1200)` (≈ 452.89 Hz).
- Deviations must be preserved for every call shape: a single note string, a
  list of note strings (elementwise), with flat (`b`/`!`) and sharp (`#`)
  spellings, and across octaves. Plain note names without a deviation
  (e.g. `'A4'`, `'C4'`) must keep returning exactly the equal-tempered
  frequencies they do today (e.g. `440.0`).
- The equal-tempered behaviour must remain available on request: passing an
  explicit `round_midi=True` must still quantize a deviated note to its
  nearest semitone (so `librosa.note_to_hz('C2-30', round_midi=True)` equals
  `librosa.note_to_hz('C2')`).
- Everything the project's own existing tests already assert must keep
  passing; in particular `python3 -m pytest tests/test_convert.py` must be
  green, and malformed note names (e.g. `'does not pass'`) must still raise
  `librosa.ParameterError`.

Do not change the git metadata of the checkout (no new commits, no rebasing,
no `git checkout`-ing other revisions): the tree must remain the same clone of
the same revision, with only the code fix applied to your working tree.
`/opt/golden`, `/solution` and `/tests` are harness-owned: do not read or
modify them. The verifier will run its own checks against your fixed tree.