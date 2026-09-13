# Non-finite pitch values crash librosa's note-name conversions

## Situation

`/app/src` is a shallow, pinned clone of the librosa repository
(`https://github.com/librosa/librosa`) at a fixed upstream commit
(checked out in detached HEAD; `git rev-parse HEAD` shows which).
The library is pure Python and is imported directly from the clone:
`PYTHONPATH` already points at it, so any edit you make inside
`/app/src/librosa/` is live for every `python3` process in this container:

```
python3 -c "import librosa; print(librosa.__file__)"
# -> /app/src/librosa/__init__.py
```

There is **no network** at trial time: `git fetch`, `curl` and any other
network use will fail. All dependencies (numpy 2.5.3, scipy 1.18.1,
numba 0.67.0, pytest, ...) are already installed; there is no build step.

The project's own unit tests run with pytest. The conversion module's test
file (including the regression cases for this bug) is in the image at
`/opt/golden/test_convert_fix.py`; run it like this:

```
python3 -m pytest -p no:cacheprovider -o addopts='' /opt/golden/test_convert_fix.py -q
```

(Omitting the `-o addopts=''` override makes pytest pick up the repository's
`setup.cfg` options, which need plugins that are not installed — always pass
it.)

## The bug

librosa converts between MIDI pitch numbers and spelled note names:
`midi_to_note` maps a MIDI number to a note string, `note_to_midi` maps a
note string back to a MIDI number, and `midi_to_svara_h` / `midi_to_svara_c`
map a MIDI number to the corresponding Indian-solfege (svara) name.

Pitch-extraction pipelines routinely feed these conversions non-finite
values: `np.nan` when no pitch is present at a frame, and `±np.inf` when an
autocorrelation overflows. In this checkout those inputs crash instead of
producing a result:

```
>>> import numpy as np, librosa
>>> librosa.midi_to_note(np.nan)
ValueError: cannot convert float NaN to integer
>>> librosa.midi_to_note(np.inf)
OverflowError: cannot convert float infinity to integer
```

so a vectorised pipeline that hits one bad entry dies mid-computation
instead of degrading gracefully. The reverse direction is broken the same
way: a missing note represented by an empty string should convert back to a
missing value, but raises `ParameterError: Improper note format: ` instead.

## What you need to do

Repair the conversion code in the checked-out tree at `/app/src` so that:

1. `midi_to_note(v)` returns the empty string `""` for every non-finite `v`
   in `{np.nan, np.inf, -np.inf}` — for scalars and for entries inside
   arrays;
2. the same non-finite inputs to `midi_to_svara_h(midi, Sa=...)` and
   `midi_to_svara_c(midi, Sa=..., mela=...)` also return `""`;
3. `note_to_midi("")` returns the numeric missing value `np.nan` instead of
   raising, while every real note string still converts to the same number
   as before (e.g. `note_to_midi("C4") == 60`);
4. every other conversion in the module — frames ⇄ samples ⇄ time, Hz ⇄
   MIDI ⇄ note (including `hz_to_note`), octaves, tuning, and the svara
   conversions for finite inputs — keeps behaving exactly as it does now.

The fixed behaviour is the contract: any non-finite or empty input yields
the sentinel result (`""` from the note-producing direction, `np.nan` from
the note-consuming direction), and every finite or properly spelled input
keeps its current result. The project's own regression tests for this
behaviour, together with the module's entire pre-existing test suite, are
the file at `/opt/golden/test_convert_fix.py`; treat that suite as
authoritative and drive your work with it — it takes well under a minute
once numba has warmed its cache.

## Constraints

- The clone at `/app/src` is the deliverable. Change in place only the
  source that implements the conversions: do not rewrite history, add
  remotes, fetch, commit, rename files, add files, or touch anything under
  `/app/src/tests/`.
- The final `git status --porcelain` must show exactly **one** modified
  file: the source you had to fix.
- `/opt/golden`, `/tests` and `/solution` are harness-owned; do not read or
  modify them.

## What the verifier checks

1. The tree is still at the pinned commit, the repository history is
   untouched, `import librosa` resolves to `/app/src`, and `git status`
   shows exactly the one modified source file.
2. `python3 -m pytest ... /opt/golden/test_convert_fix.py` passes in full:
   the upstream regression cases for this bug plus every pre-existing test
   of the conversion module.
3. Hidden cases: scalar, array and list inputs across all four fixed entry
   points — including dtypes, keyword arguments, `Sa`/`mela` values and
   `hz_to_note` round trips the regression cases do not use — all produce
   the sentinel results, and finite/named inputs still convert correctly.

Deliverable: the repaired `/app/src` tree.