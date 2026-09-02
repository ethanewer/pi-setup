# Quartz Grove — reproducible scientific environment & dependency conflict resolution

**Quartz Grove** runs a numerical-analysis post-processing cluster. Several
consumers depend on a shared base array engine (`numpy`) but pin incompatible
ranges of it. You must build a reproducible, pinned environment for the cluster
that:

1. declares the dependency set (`requirements.txt`) with **exact** version pins;
2. resolves pairwise package-version conflicts so the resolver yields **one
   consistent pinned set** (literature lock `environment.lock`);
3. installs that set into an **isolated** venv **without touching a pre-existing
   global numpy** in the system Python, and records the preserved global version
   (`frozen_versions.json`);
4. runs the provided reference example under the venv and saves its log
   (`example_check.log`).

The reference environment is deliberately task-shaped: no `conda`, no heavy
frameworks — a lean pip venv is exactly what passes.

## Provided inputs (never hand-written answers)

- `/app/spec.json` — the dependency survey (JSON). See **Spec schema** below.
- `/app/example_check.py` — the reference example you must execute under the
  venv. Do **not** edit it.
- `/app/.global_numpy_original` — the exact value the shared global `numpy`
  (in the system interpreter) has today; it must remain exactly this.
- The `QUARTZ_GROVE_SESSION` environment variable is baked into the image.

## Deliverables you must produce

| Path | What it is |
|------|------------|
| `/app/resolve.py` | a general, runnable dependency resolver (self-contained Python 3) |
| `/app/environment.lock` | the JSON lock produced by running `resolve.py` on the primary spec |
| `/app/requirements.txt` | the pip manifest of the locked set, `==`-pinned |
| `/app/frozen_versions.json` | `{"preserved":{"numpy":"<original global version>"}}` |
| `/app/example_check.log` | stdout of running the example under the venv |

`/app/venv` — a Python virtual environment **created by you** at
`/app/venv` in which the three pinned packages are actually installed.

## Spec schema (`spec.json`)

```json
{
  "interface": "numpy",
  "candidates": ["1.26.4", "1.24.4", "..."],
  "catalogue": {
     "<package>": [
        {"numpy": ">=1.22.4,<2.0.2", "version": "2.2.2"},
        {"numpy": ">=2.0.2",        "version": "2.3.3"}
     ]
  },
  "modules": [
     {"name": "frames", "package": "pandas", "numpy": ">=1.22.4"},
     {"name": "solver", "package": "scipy",  "numpy": ">=1.24.4"}
  ]
}
```

- `interface`: target (call it `numpy`) whose version centralizes every module.
- `candidates`: available versions of that interface to choose from.
- `catalogue`: for each dependent package, the package-versions it ships for
  which interface ranges.
- `modules`: dependents; each states its required interface range and its
  package.

**Version numbers** are bare dotted integers (e.g. `1.26.4`) — never
`v`-prefixed (`v1.26.4`), never operator-prefixed (`==1.26.4`), never spaces
inside a token. A **range** is a comma-separated conjunction of comparison
clauses, each clause being one of `>=`, `<=`, `>`, `<`, `==` immediately
followed by a valid dotted version, with no spaces inside a token.

## Tasks

### 1. Resolve the conflict in `/app/spec.json`

The original `/app/spec.json` contains three modules: `frames`, `solver` and a
deprecated `legacy` backend. The `legacy` module pins `numpy` to `"<1.22.0"`
while the current `solver` requires `numpy>=1.24.4`. Those two ranges have **no
common version** — a genuine pair that must no longer co-occur.

Edit `/app/spec.json` (it is intended to be edited) so the shipped dependency
set becomes consistent: the deprecated `legacy` provider must be removed (or
de-constrained). After your edit, **every candidate version that any module
will accept must have a common version.** In the same original edit the
`frames` and `solver` modules remain, and the resolver must pick the newest
satisfying version.

### 2. Write `/app/resolve.py`

`resolve.py` must be a general program you author, invoked as:

```
python3 /app/resolve.py --spec <SPEC_JSON>
```

Behaviour — exact, deterministic exit contract (this is what the verifier
asserts):

- **Malformed spec** — JSON that cannot load, `candidates` missing/empty/with a
  token that is not a dotted version, a `module` missing `name`/`package`/`numpy`,
  duplicate module `name`, an unknown `package` (absent from `catalogue`), a
  `catalogue` entry missing `numpy` or `version`, or any range with a token that
  is not one of `>=`,`<=`,`>`,`<`,`==` followed by a valid dotted version:
  print **nothing to stdout**, a one-line diagnostic to stderr, exit code **1**.
- **Genuine conflict** — structurally valid but no candidate version satisfies
  every module (empty intersection, e.g. `>=1.25.0` vs `<1.20.0` with candidate
  list `[1.19.5, 1.23.3]`): print nothing to stdout, one stderr line, exit **2**
- **Success** — print exactly **one JSON object** lock to stdout and exit **0**:

```
{"interface": "numpy", "numpy": "1.26.4",
 "modules": {"frames": {"package": "pandas", "version": "2.2.2"},
             "solver": {"package": "scipy", "version": "1.13.1"}},
 "consistent": true}
```

a) Choose the **highest** candidate interface version that:
   - satisfies **every** module's range, and
   - for **each** module's package has at least one catalogue entry whose range
     is satisfied by that candidate.
b) For each module, pick the **highest** catalogue package version compatible
   with the chosen interface.

Apply plain dotted-integer comparison (`1.26.4` beats `1.2.4`). Only
leading-dot integers are valid version tokens; PEP 440-style suffixes (e.g.
`1.26.4.post1`, `1.26.4+local`, pre-releases) are **not** part of the format
— keep ranges strict and simple.

### 3. Produce the lock and the manifest

```
python3 /app/resolve.py --spec /app/spec.json > /app/environment.lock
```

Now write `/app/requirements.txt` so the venv port of those three written
versions install cleanly and exactly:

```
numpy==1.26.4
pandas==2.2.2
scipy==1.13.1
```

(with whatever exact versions the lock holds; each on its own line, `==` name).

### 4. Install into your isolated venv

```
python3 -m venv /app/venv
/app/venv/bin/pip install --no-cache-dir -r /app/requirements.txt
```

The venv is where the three real packages get installed. **Never** run a
`pip install` that targets the **system** python (`python3 -m pip` without a
venv / `--break-system-packages`): doing so would upgrade the shared global
`numpy` and fail the "preserved global dependency" check. The system Python is
PEP-668 externally-managed, which both nudges you toward a venv and makes a
global upgrade the failure you must avoid.

### 5. Record the frozen global version

Write `/app/frozen_versions.json` as:

```json
{"preserved": {"numpy": "1.26.0"}}
```

where `1.26.0` is the **original** global `numpy` version (see
`.global_numpy_original`). Do not meddle: this must match the actual untouched
global version.

### 6. Run the example to confirm

Run the provided example with the venv's interpreter:

```
/app/venv/bin/python /app/example_check.py > /app/example_check.log 2>&1
```

The example imports all three libraries, verifies each installed version equals
its pin in `requirements.txt`, does real numeric work, and prints exactly one
line `QUARTZ_GROVE_OK sig=<16-hex>`, a signature derived from the session token
and actual installed versions.

`/app/example_check.log` must contain exactly that line. Do not hand-write the
log — the verifier re-runs the example and compares bytes, and the signature
cannot be forged without the session token and the real installed versions.

## What the verifier checks (summary)

- that `/app/requirements.txt` pins the three packages with `==` and installs
  into a **fresh** venv honoring every pin (no solver incompatibility);
- that the primary spec's modules still have a **common candidate version**
  (disjoint pair removed);
- that `/app/environment.lock` equals the resolver's output and matches the
  manifest;
- that `resolve.py` re-run **generalizes** across multiple hidden specs,
  including a tight range, a genuine conflict (exit 2) and a malformed spec
  (exit 1);
- that the global `numpy` in the system python is **exactly** its original
  version and `frozen_versions.json` records that original;
- that running the reference example under `/app/venv` yields exit 0 and the
  log byte-matches a re-run with the correct signature;
- that the image stays lean (footprint budget, no accidental frameworks).

## Constraints

- Do **not** modify `/app/example_check.py` or `/app/.global_numpy_original`.
- `/app/spec.json` is yours to edit; everything else deliverable the deliverables.
- Keep it minimal / lean: isolated venv only; the checker rejects unbacked extra
  frameworks (e.g. `torch`/`tensorflow`) and a bloated total footprint.
- Version compare uses plain dotted integers; ranges use only
  `>=` `<=` `>` `<` `==` tokens separated by commas.

## Acceptance flow (for your own local dry-runs)

```
python3 -m venv /tmp/dev ; /tmp/dev/bin/pip install numpy pandas scipy
```
or simply follow steps 2–6 above and re-run `resolve.py` on hidden specs.

When done, both directions must hold: after running the full solution the
verifier writes 1; on a pristine image (the environment alone) it writes 0.