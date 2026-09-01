# quill-vane — transcribe algorithms from photographed snippets

The **Fenwick Print Collective** digitized part of its internal algorithms
handbook by photographing printed pages. The photos are small, low-contrast and
speckled, so character-recognition tools do **not** yield clean text on them:
operators, underscores and digits come out mangled. You must read the three
photographed Python snippets yourself and transcribe their **exact logic and
constants**, then reproduce that logic in working programs. Any single misread
character or operation changes the computed result and fails.

## Environment

- Working directory: `/app`. Python 3.12 (standard library only; **no**
  third-party packages are needed or allowed).
- The photographed snippets are at:
  - `/app/snippets/func_a.png`
  - `/app/snippets/func_b.png`
  - `/app/snippets/func_c.png`
  Each is a grayscale photograph of a complete, self-contained Python function.
  You may not modify these images.
- `/app/probe.json` holds one **probe argument** per function, e.g.
  `{"func_a": 310, "func_b": "GraniteFjord7", "func_c": [5, 8, ...]}`.

## Deliverables (all required)

1. `/app/eval_funcs.py` — a runnable program with **exactly** this interface:
   ```
   python3 /app/eval_funcs.py <snippets_dir> <probe_json> <output_json>
   ```
   It must **implement** the three photographed functions itself (`func_a`,
   `func_b`, `func_c`) — transcribed faithfully, with the same numeric
   constants, loop bounds, operators and control flow shown in the photos —
   then evaluate each function on the corresponding argument from
   `<probe_json>` and write the results to `<output_json>`.
2. `/app/answer.json` — the output produced by running your program on the
   shipped fixture:
   ```
   python3 /app/eval_funcs.py /app/snippets /app/probe.json /app/answer.json
   ```

## Output format

`<output_json>` must be a JSON object with exactly these keys:

```json
{"func_a": <int>, "func_b": <string>, "func_c": <int>}
```

- `func_a` takes an integer `n` and returns an integer.
- `func_b` takes a string `s` and returns a string.
- `func_c` takes a list of integers and returns an integer.

## What the grader does

The verifier re-runs your `eval_funcs.py` unchanged on **hidden probe files**
(again paired with the same photographed snippets) and compares the results to
ground truth computed from the true transcriptions. A program that only
reproduces `/app/answer.json` (e.g. by hard-coding the shipped probe's answers
or ignoring its arguments) will fail those hidden runs. `eval_funcs.py` must
work for any argument values of the types described above.

## Constraints

- Standard library only; no network access.
- Do not modify anything under `/app/snippets/` or `/app/probe.json`.
- The verifier applies a tolerance only where explicitly stated; integer and
  string results are compared exactly.
