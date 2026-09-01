# Garnet Vault — recover the activation codes

The Garnet Vault team lost the release activation codes for build 2031.4.
All that survives is the checker source at `/app/src/vault.c` (and a compiled
copy of it at `/app/src/vault`, if you want a reference oracle for spot
checks). Your job is to recover the valid activation code for **every
activation profile that is enabled in this build** and leave them in
`/app/codes.txt`.

## Deliverable: `/app/codes.txt`

A plain-text file with one line per profile you are shipping a code for:

```
<PROFILE>=<CODE>
```

- `<PROFILE>` is a single character naming a profile in the checker's profile
  table (see the source).
- `<CODE>` is exactly the activation code string the checker accepts for that
  profile.
- Only profiles **enabled in this build** can have valid codes; shipping a
  line for a profile that is disabled in this build will fail verification.
- Blank lines are allowed; no other content is allowed.

Example of the format (values are placeholders, not real codes):

```
A=XXXX16CHARSXXXXX
B=YYYY16CHARSYYYYY
```

## Rules

- The codes must be **genuinely valid for the recorded validation logic in
  `/app/src/vault.c`**. The verifier compiles that source **fresh from disk**
  at several optimization levels and runs the freshly built checkers against
  every line of your `codes.txt`; every shipped profile must print
  `ACCEPT` under **every** fresh build. A code that only satisfies a patched
  or hand-tampered binary will not survive that.
- **Do not modify `/app/src/vault.c`** (the verifier checksums it against the
  release manifest and refuses to grade a tampered source). Do not modify or
  delete `/app/src/vault`. You may create new files anywhere under `/app`.
- You may use the prebuilt `/app/src/vault` binary as an oracle for probing,
  but the answer must be correct on its own merits.
- No network access is needed; `gcc` and `python3` are installed.

## Code format (from the release spec)

An activation code is exactly 16 characters drawn from the 32-symbol
alphabet embedded in the checker (no I, O, 0, or 1). The checker applies its
own per-character chain, a checksum gate, and a rolling-hash gate; all three
must hold simultaneously. There is exactly one code per enabled profile that
satisfies the chain for that profile's seed.

## How you will be graded

The verifier will, in a fresh copy of the environment:

1. Verify `/app/src/vault.c` is byte-identical to the release manifest.
2. Recompile it with `gcc -O0`, `gcc -O2`, and `gcc -Os`.
3. Parse `/app/codes.txt` and, for every shipped line, run each of the three
   fresh binaries with that profile and code. Each must print `ACCEPT`.
4. additionally confirm that a deliberately wrong probe code is `REJECT`ed,
   so a checker that accepts anything cannot pass.

Partial credit is not given: all enabled profiles must verify.
