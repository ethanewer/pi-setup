# Loomis relay vault recovery

You are recovering the vault keycard for a Loomis deep-space relay station.
Everything lives in `/app`. **Do not modify** `/app/keycard_gen.py`. Never read
`/tests` — it is hidden and irrelevant to your work.

## The station schedule

`/app/keycard_gen.py` is the station's keycard generator. Read it. It defines:

- `activated(serial)` — whether a small integer `serial` is on the active duty
  roster (a compact gate). Only rostered serials ever matter; the full serial
  space `[0, SERIAL_HI)` is far larger than the roster and must never be
  brute-forced by trying every token.
- `emit_keycard(serial)` — what the flaky station printer prints for that
  serial. It is frequently **not** a usable keycard.
- `is_well_formed(token)` — the exact keycard format predicate.
- `SERIAL_HI`, `VAULT_PIN`, `VAULT_MODULUS` — the constants described below.

## Deliverables (create all of these)

| Path | Meaning |
|------|---------|
| `/app/solve.py` | your solver (interface below) |
| `/app/candidates.txt` | every well-formed keycard, one per line (see Part 1) |
| `/app/answer.json` | the vault-recovery result (see Part 3) |

## Part 1 — enumerate keycard candidates (tight format, rostered serials only)

A **candidate (well-formed keycard)** satisfies **all** of:

- exactly **20 characters**,
- only **uppercase letters (A–Z) and decimal digits (0–9)** — no lowercase, no
  separators, no spaces, no punctuation,
- **begins** with the fragment `VLT`,
- **ends** with the fragment `K7`.

Write `/app/solve.py` so that on each run it:

1. Scans **every rostered serial** (honor `activated`; never iterate the naive
   full serial space), generates that serial's `emit_keycard` output, and
   retains **only the outputs that satisfy the format predicate** — the
   well-formed-keycard scheme documented above, exactly as implemented by the
   generator's `is_well_formed`. Apply it strictly and exactly; never relax it
   and never extend it.
2. Writes `/app/candidates.txt` with **each** retained candidate, one per line,
   in ascending serial order (duplicates kept if two serials ever print the
   same token).
3. Exits 0.

**Do not tighten the format any further.** In particular: tokens containing the
easily-confused characters `O`, `0`, `I`, `1` are perfectly valid and MUST be
retained; do not invent extra rules (no "no repeated pairs", no minimum digit
count, no checksum of your own). Dropping the one candidate the vault needs by
over-tightening the format loses the whole task — the point is to write down
**every** string that matches the documented scheme, not to guess the final
unique value up front.

## Part 2 — SHA-256 residue pin (select the vault keycard)

The vault ticket pins the residue `VAULT_PIN` modulo `VAULT_MODULUS` (both are
module constants of the generator):

> The active (vault) keycard is the **unique** candidate whose SHA-256 hex
> digest, read as a base-16 integer (`int(digest, 16)`), is congruent to
> `VAULT_PIN` modulo `VAULT_MODULUS`.

Compute `sha256(token.encode("utf-8")).hexdigest()` for each candidate, take
`int(digest, 16) % VAULT_MODULUS`, and find the unique candidate whose residue
equals `VAULT_PIN`. That token is the vault keycard; its serial is the
**active serial**.

## Part 3 — the recovery result

Write `/app/answer.json` with **exactly and only** these keys:

```json
{
  "keycard": "<the active vault keycard>",
  "active_serial": <integer serial of the active keycard>,
  "candidate_count": <number of lines written to /app/candidates.txt>,
  "pin": <VAULT_PIN>,
  "modulus": <VAULT_MODULUS>
}
```

## Solver interface (reusable)

```
python3 /app/solve.py <generator.py> <candidates_out.txt> <answer_out.json>
```

The solver takes the generator module path as its **first argument** (load it
with `importlib`, never by hard-coded import), enumerates candidates per
Part 1, selects the vault keycard per Part 2, writes the two output files at
the given paths, and exits 0. The visible run is:

```
python3 /app/solve.py /app/keycard_gen.py /app/candidates.txt /app/answer.json
```

## Grader behavior

The grader re-runs `/app/solve.py` **unchanged** against fresh generator
modules mounted under `/tmp` — different serial ranges, different keycard
lengths and prefix/suffix fragments (the visible `20`/`VLT`/`K7` values are
NOT universal: drive the format from each module's `is_well_formed` and its
`SERIAL_HI`/`VAULT_PIN`/`VAULT_MODULUS` constants) — then re-derives the
expected candidate list and vault selection from each module and compares
your outputs exactly. Do not hard-code the visible constants, fragments, or
answers. If the generator of the day emits several well-formed tokens, all
of them belong in the candidates file — selection happens only in Part 2.

No network access is needed; Python 3.12 standard library only.
