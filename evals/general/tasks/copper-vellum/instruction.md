# copper-vellum — the photographed control-flow routine

The Meridian Line ops office digitized an old engineering runbook. The only
surviving copy of a small but non-trivial control-flow routine is a
**photograph**: `/app/routine.png`. The plain-text source was lost, and
character-recognition tools handle this photo poorly — they mangle operators
and punctuation, drop indentation, and misread ambiguous glyphs, so you must
transcribe the routine **visually and exactly**. Every constant, operator,
comparison direction, and branch arm matters: a single misread character
changes every result.

## Environment

- Working directory: `/app`. It already contains the photo `/app/routine.png`
  and the input `/app/input.json`. Python 3.12 is available as `python3`.
- **Do not modify `/app/routine.png` or `/app/input.json`.**

## Deliverables (both required)

1. `/app/routine.py` — a runnable Python program with this interface:
   ```
   python3 /app/routine.py <input_json> <output_json>
   ```
   It reads an input JSON and writes the answer JSON (format below). It must
   work on **any** input of the same schema — the verifier re-runs it, as-is,
   on hidden inputs — and it must not hard-code the shipped input values.

2. `/app/answer.json` — the answer your program produces for the shipped
   `/app/input.json`:
   ```
   python3 /app/routine.py /app/input.json /app/answer.json
   ```

## Input schema

`<input_json>` holds a single JSON object:

```json
{"a": <non-negative int>, "b": <non-negative int>}
```

Both `a` and `b` are non-negative integers below 4096. Hidden inputs follow
the same schema.

## The photographed routine

`/app/routine.png` shows a short legacy Python function (preceded by a
comment line). Its shape: derive two quantities from `a` and `b` with
arithmetic and bitwise operations, combine them under a **two-way branch**
whose polarity (which comparison sends control which way, and what each arm
adds or subtracts) is only visible in the photo, fold with an integer floor
division, and reduce modulo a fixed modulus near 1000. Transcribe it
**exactly** — the constants, the operators, the comparison, the branch arms,
and the modulus — and evaluate it for the input's `a` and `b`.

The result of the photographed function for the given inputs is reported as
the integer field `truth_id`.

## The auxiliary chain (documented here)

Your program must also evaluate this auxiliary chain on the same inputs, in
two variants:

- `v1 = a * 2` (i.e. `a` shifted left by one)
- `v2 = b ^ 33` (bitwise XOR with thirty-three)
- `v3 = v1 + v2`
- `v4 = v1 | v3` (bitwise OR)

**Unguarded variant** (reported under `"samples"`):
- `v5 = v4 >> 2` (arithmetic right shift by two, i.e. floor division by 4)

**Guarded variant** (reported under `"trace"`): before computing `v5`, the
value is corrected first:
- if `v3 > 37` then `v4 = v4 ^ 26` (XOR with twenty-six)
- otherwise `v4 = v4 + 37`
- then `v5 = v4 >> 2`

Each `v1`…`v5` is a number; emit it as a JSON number with any integer-valued
entry kept exact (e.g. `92` or `92.0`).

## Required output JSON

The output file must be valid JSON with exactly these keys:

```json
{
  "truth_id": <int>,
  "samples": {"v1": <num>, "v2": <num>, "v3": <num>, "v4": <num>, "v5": <num>},
  "trace":   {"v1": <num>, "v2": <num>, "v3": <num>, "v4": <num>, "v5": <num>}
}
```

- `truth_id` — what the photographed routine returns for the input's `a, b`.
- `samples` — the five chain values in the **unguarded** variant.
- `trace` — the five chain values in the **guarded** variant.
- All three sub-objects are required with exactly the keys shown.

The verifier compares `truth_id` exactly and all chain values numerically
(small float tolerance), so the photographed constants must be read exactly.

## Edge cases probed by the verifier's hidden inputs

- Both branch polarities of the photographed routine (the comparison going
  either way).
- A modulus wrap (the folded value exceeding the modulus).
- Both arms of the documented guard (`v3 > 37` true and false).
- Values of `a` and `b` of different magnitudes, including zero.

## Constraints

- Standard library only; no network access at run or verify time.
- The verifier invokes `python3 /app/routine.py` unchanged on hidden inputs
  that follow the same schema — do not hard-code the shipped fixture.
- Do not modify `/app/routine.png` or `/app/input.json`.

Write `/app/routine.py` and run it on the shipped input so `/app/answer.json`
exists and is correct.
