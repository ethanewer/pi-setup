# Beacon attestation via SHA-1 structural counts

The attestation station for the **Cobalt** channel fleet is locked. You must
build a reusable attestation program that identifies the beacon code whose
SHA-1 digest has a pinned structural property, and record the result.

## Environment

- Working directory: `/app`. It already contains:
  - `/app/beacon_gen.py` — the beacon generator module (see below),
  - `/app/beacon.target` — the pinned structural target (one line,
    `letters=<N>`).
- Python 3.12 is available as `python3`. Standard library only.
- **Do not modify `/app/beacon_gen.py` or `/app/beacon.target`.**

## The structural rule (exact)

For a candidate code string `C` (encoded UTF-8):

1. Compute `sha1(C)` and take the **40-character lowercase hex digest**.
2. Count how many characters of the digest are **hex letters**, i.e. any of
   `a b c d e f` (digits `0-9` do not count).
3. That count is the code's **letter-count**.

The pinned target in `/app/beacon.target` (`letters=<N>`) selects the codes
whose letter-count is **exactly** `N`.

## Deliverables (both required)

1. `/app/solve.py` — a runnable Python program with this interface:

   ```
   python3 /app/solve.py <generator_py> <target_file> <output_json>
   ```

   It must:

   - Import the generator module given by `<generator_py>`. A conforming
     generator module defines the integers `SEED_LO` and `SEED_HI`, the
     strings `PREFIX` and `SUFFIX`, and the function
     `beacon_code(seed: int) -> str`.
   - Read `<target_file>`; its active line is `letters=<N>` (parse the integer
     after `letters=`; ignore blank lines).
   - Enumerate **every integer seed** in the half-open range
     `[SEED_LO, SEED_HI)`, compute each seed's code with `beacon_code`, and
     keep every code whose letter-count (rule above) equals `N`.
   - Write a JSON object to `<output_json>` with **exactly** these keys:

     ```json
     {
       "target": <N as int>,
       "matches": ["<code>", "..."],
       "match_count": <number of matches as int>
     }
     ```

     `matches` lists the matching codes **in ascending seed order** (duplicates
     are impossible in this fixture family, but if a value repeated it would be
     listed once per seed that produced it).

2. `/app/answer.json` — the output your program produces **when run on the
   provided fixtures**:

   ```
   python3 /app/solve.py /app/beacon_gen.py /app/beacon.target /app/answer.json
   ```

## Edge cases the grader probes with hidden fixtures

- The verifier copies **fresh generator modules and target files** (different
  prefixes, suffixes, seed ranges, derivation arithmetic, and target values)
  to `/tmp` and runs your `/app/solve.py` against them unchanged. Do **not**
  hard-code the visible seed range, prefix/suffix, arithmetic, or target.
- Targets for which **no** seed matches must yield `"matches": []` and
  `"match_count": 0` (with `"target"` still reported).
- A target file may contain blank lines around the active `letters=` line.
- Hex-letter counting is on the lowercase hex digest; uppercase input is
  impossible (hexdigest is lowercase), and digits never count as letters.

## Constraints

- No network access at verify time; standard library only.
- `sha1` here is the plain SHA-1 of the UTF-8 encoding of the code string —
  no salts, prefixes, or separators.
