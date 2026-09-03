# Pearl Gasket — symbolic harmonic analysis of a chorale score

The **Linden Choir** archive stores short chorale-style chord progressions in a
lightweight JSON symbolic format and needs a deterministic, dependency-free
analyzer that turns them into a complete functional analysis: roman numerals,
triad qualities, inversions, cadences, and parallel perfect intervals. There
are **no audio files and no music libraries** — the entire task is symbolic.
Pure Python stdlib (`json`, `re`, `sys`) is required; nothing else is
installed and there is no network.

## Fixture already in `/app`

- `/app/score.json` — the visible score: a C-major chorale snippet. Shape:

```json
{
  "key": "Cmaj",
  "chords": [
    {"beat": 1, "duration": 1, "notes": ["C3", "G3", "C4", "E4"]}
  ]
}
```

- Every chord object has an integer `beat` (>= 1), an integer `duration`
  (>= 1), and a non-empty `notes` list. The `chords` list itself may be empty
  (a valid input producing an empty analysis).
- `notes` entries follow the grammar: **capital letter A–G, an optional single
  accidental `#` or `b`, then a single octave digit 0–9** (e.g. `"C4"`,
  `"F#3"`, `"Bb4"`, `"Eb3"`, `"B#3"`, `"Fb2"`). The list is unordered; voices
  are re-derived by sorting.

## Note and key grammar (exact)

- Pitch classes: `C=0, D=2, E=4, F=5, G=7, A=9, B=11`, shifted by `#` (+1) or
  `b` (−1), mod 12. MIDI value = `(octave + 1) * 12 + pitch class` (`C4` = 60).
- `key` is a capital letter A–G, an optional single `#`/`b`, followed by
  exactly `maj` or `min` (e.g. `"Cmaj"`, `"Gmaj"`, `"Dmin"`, `"Ebmaj"`,
  `"F#min"`). Anything else (`"Hmaj"`, `"Cmajor"`, `"cmaj"`) is malformed.

## Diatonic triad pools (the complete theory ruleset)

Pitch classes below are **offsets from the tonic** of the declared key.

**Major keys** — scale degrees 1..7 of the major scale `[0,2,4,5,7,9,11]`:

| Degree | Roman | Quality | Pitch-class set |
|--------|-------|---------|-----------------|
| 1 | I | major | {0,4,7} |
| 2 | ii | minor | {2,5,9} |
| 3 | iii | minor | {4,7,11} |
| 4 | IV | major | {5,9,0} |
| 5 | V | major | {7,11,2} |
| 6 | vi | minor | {9,0,4} |
| 7 | vii° | diminished | {11,2,5} |

**Minor keys** — the natural-minor triads on degrees 1..7 (natural minor
scale `[0,2,3,5,7,8,10]`, raised 7th = 11) plus the two raised-7th variants
**V** (major dominant) and **vii°** (leading-tone diminished):

| Roman | Quality | Pitch-class set |
|-------|---------|-----------------|
| i | minor | {0,3,7} |
| ii° | diminished | {2,5,8} |
| III | major | {3,7,10} |
| iv | minor | {5,8,0} |
| V | major | {7,11,2} |
| v | minor | {7,10,2} |
| VI | major | {8,0,3} |
| VII | major | {10,2,5} |
| vii° | diminished | {11,2,5} |

The degree sign is U+00B0 (`"vii°"`, `"ii°"`). Roman case encodes quality:
uppercase = major, lowercase = minor, lowercase + ° = diminished.

## Per-chord analysis (exact algorithm)

1. Compute the set `S` of distinct pitch classes in the chord's notes.
2. Candidates = all pool triads whose pitch-class set is a **subset** of `S`
   (in the shipped fixtures every chord has 3 distinct pitch classes and
   exactly one candidate).
3. If there are no candidates the input is malformed (see CLI contract).
4. More than one candidate — fixed tie-break: (a) if exactly one candidate has
   its **root** equal to the bass pitch class, take it; (b) otherwise prefer
   the lower root pitch class, then the pool table order (top to bottom). The
   fixtures never trigger this; it is specified for determinism only.
5. Bass = the **lowest note** by MIDI value (its pitch class).
6. Inversion: bass == root → `""`; bass == third → `"6"`; bass == fifth →
   `"64"`.
7. `roman` = the base numeral plus the inversion suffix (`""`, `"6"`, `"64"`),
   e.g. `"V6"`, `"vii°6"`, `"I64"`. `quality` = the triad quality from the
   table.

## Cadences (exact)

- A chord index `i` is **phrase-final** iff `i == len(chords) - 1` **or**
  `chords[i].duration >= 2`.
- Cadences are checked **only** at phrase-final chords `i >= 1`, on the pair
  `(chords[i-1], chords[i])`. The value is assigned to `chords[i].cadence`,
  first matching rule wins:
  1. **PAC** — previous roman is `"V"`, current roman is `"I"` or `"i"`, and
     the highest note (by MIDI) of the current chord is the tonic pitch class.
  2. **IAC** — previous roman ∈ {`V`, `V6`, `vii°`, `vii°6`} and current roman
     ∈ {`I`, `I6`, `i`, `i6`} (and not PAC).
  3. **HC** — current roman is `"V"`.
  4. **PLAGAL** — previous roman ∈ {`IV`, `iv`} and current roman ∈ {`I`, `i`}.
  5. otherwise `null`.
- The first chord (no predecessor) and all non-phrase-final chords get `null`.

## Parallel perfect intervals (exact)

Detected **between consecutive chords only**:

1. Sort each chord's notes by ascending MIDI value (stable sort for identical
   notes).
2. For adjacent chords `A`, `B`: let `n = min(len(A), len(B))` and compare the
   first `n` sorted positions ("rank voices").
3. For every rank pair `(j, k)` with `0 <= j < k < n`:
   `dA = (midiA[k] - midiA[j]) % 12`, `dB = (midiB[k] - midiB[j]) % 12`.
4. `P5` iff the value is `7`. `P8` iff the value is `0` **and** the two notes
   differ (two identical notes form a unison, not an octave).
5. When `dA` and `dB` are both `P5` (or both `P8`), report
   `{"beats": [A.beat, B.beat], "interval": "P5"}` (resp. `"P8"`).
6. Report order: score order of the adjacent pairs, then rank pair `(j, k)`
   ascending. Never merge or deduplicate entries (a rank pair can only ever be
   P5 *or* P8).

## Output schema (exact)

`/app/analysis.json` — exactly these top-level keys:

```json
{
  "chords": [
    {"beat": 1, "roman": "I", "quality": "major", "inversion": "", "cadence": null}
  ],
  "parallels": [
    {"beats": [3, 4], "interval": "P5"}
  ]
}
```

- `chords`: one object per input chord, in input order, with exactly the keys
  `beat`, `roman`, `quality`, `inversion`, `cadence`.
- `quality` ∈ {`"major"`, `"minor"`, `"diminished"`}; `inversion` ∈ {`""`,
  `"6"`, `"64"`}; `cadence` ∈ {`null`, `"PAC"`, `"IAC"`, `"HC"`, `"PLAGAL"`}.
- `parallels`: entries as defined above; `beats` = the two chords' beat fields.

The output must be **deterministic**: identical input always yields identical
output. The grader compares parsed JSON, so whitespace/indentation is free,
but list order and values are not.

## CLI contract

```
python3 /app/analyze.py <score.json> <analysis.json>
```

- Reads the score JSON, computes the analysis, writes the analysis JSON
  (UTF-8), exits `0`.
- On **any** error — missing/unreadable input file, invalid JSON, malformed
  key or note, missing chord fields, or a chord matching no diatonic triad —
  print a short message to stderr, exit **non-zero**, and **do not create**
  the output file.

## Deliverables

1. `/app/analyze.py` — the analyzer CLI above.
2. `/app/analysis.json` — the analysis of `/app/score.json`, exactly what
   `analyze.py` produces for it.

## Constraints

- Pure Python stdlib only (`json`, `re`, `sys`). No third-party or music
  libraries, no network, no audio. CPU only.

## How the grader probes it

The verifier runs `/app/analyze.py` on the visible score and on **hidden
scores you have not seen** — a G-major progression with planted parallel
fifths, a D-minor progression with a planted parallel octave and a deceptive
`V → VI` ending, an E-flat-major progression with a plagal `IV → I` ending, an
all-diminished progression, a duplicated-note edge case, and an empty
progression — each twice (determinism check). Every output is compared against
the verifier's **own independent implementation of the rules above**,
recomputed from the fixtures. It also checks that `/app/analysis.json` equals
that recomputation of the visible score, and feeds malformed inputs (bad note,
off-key chord, bad key, missing fields, missing file) that must be rejected
with a non-zero exit and no output file. A hardcoded visible analysis fails
every hidden case.