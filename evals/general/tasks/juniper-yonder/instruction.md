# Juniper Yonder — reduced-cipher crypto recovery

You are working inside `/app` on a container that contains a `crypto-lab` scenario. A small
team left behind several interdependent artifacts in `/app/workspace`. Your job is to build
**one reusable Python tool**, `/app/attack.py`, that recovers everything, and to run it on
`/app/workspace` so that **four files** exist under `/app`:

| deliverable | contents |
|---|---|
| `/app/attack.py` | your reusable tool (it is itself a deliverable) |
| `/app/keys` | the recovered reduced-cipher round keys |
| `/app/plaintexts.txt` | one decrypted plaintext per line |
| `/app/name.txt` | the isolated secret word, persisted with exact normalization |

All /app artifacts are byte-checked by a verifier, so follow the exact formats below.

## Scenario contents (`/app/workspace/`)

`/app/workspace/` contains:

- `cipher_info.py` — the YONDER **reduced block cipher** reference: `SBOX`, `INVBOX`,
  `encrypt_block(P,k0,k1)` and `decrypt_block(C,k0,k1)`. The real key is **not** in this file.
- `oracle.c` — the same cipher in C (source; also just reference). It contains **no key**.
- `yonder_enc` — a compiled oracle binary. It reads one line of hex plaintext from stdin and
  prints one line of hex ciphertext to stdout. Its two low-bit round keys (`k0`, `k1`, each
  8 bits) are baked in at build time and are **not readable** from any file. This is your
  chosen-plaintext oracle.
- `ciphertexts.txt` — the ciphertexts you must decrypt. Each line is a 4-hex-digit 16-bit
  ciphertext block; each block is the result of encrypting **2 plaintext bytes**.
- `cryptogram.txt` — a substitution cryptogram (a note).
- `clue.json` — a clued mapping used to decode the cryptogram.
- `encoded/` — files whose **bytes are irrelevant**; it is their **filenames** that matter
  (see stage 4).
- `src/` — a tree of plaintext source files that must each be encrypted with a crypto CLI
  (see stage 6).

## The task, stage by stage

### 1. Reduced-cipher key recovery (chosen-plaintext differential)

The cipher in `cipher_info.py` is a balanced 2-round Feistel over a 16-bit block:

```
L,R = (P>>8)&0xff, P&0xff
L, R = R, L ^ SBOX[(R ^ k0) & 0xff]      # round 1
L, R = R, L ^ SBOX[(R ^ k1) & 0xff]      # round 2
C = (L<<8) | R
```

Because the round-1 internal state `R1 = L0 ^ SBOX[(R0 ^ k0) & 0xff]` is emitted as the **high
byte of the ciphertext**, a chosen-plaintext probe that pins `k0` and `k1` directly; given one
(or, for robustness, several) chosen plaintext `(L0, R0)`, compute `R1 = high byte`, then
`y0 = L0 ^ R1` ⇒ `k0 = R0 ^ INVBOX[y0]`, and `R2 = low byte` gives
`k1 = R1 ^ INVBOX[R0 ^ R2]`. Confirm across a second chosen plaintext (a chosen **difference**)
so the recovered pair is exact.

Write a function:

```python
def recover_key(encrypt):
    # encrypt(p:) -> ciphertext int  ; returns (k0, k1)
    ...
```

that mounts the chosen-plaintext attack by calling `encrypt` with your chosen plaintexts and
returns `(k0, k1)`.

### 2. Decrypt every ciphertext → one plaintext per line

Using `decrypt_block(C, k0, k1)`, decrypt **every** line of `ciphertexts.txt`. Each decrypted
16-bit block holds 2 ASCII bytes — write them as two characters on **one line**. Write one
plaintext line **per ciphertext line**, in the same order, to `/app/plaintexts.txt`. Do not
skip any ciphertext.

### 3. Cryptogram → passcode and secret word

`cryptogram.txt` is a note that was letter-substituted. `clue.json` contains a JSON object with
a key `decodes_letter_to`: a mapping from each **encoded** letter to the **plaintext** letter it
decodes to (case-insensitive; non-letters are unchanged). Apply the mapping to every character
of the note (preserve case) to recover the plaintext note.

The decoded note contains two fields separated by `=`:

- `PASS=<value>` — the value right after `PASS=` stops at the next space, comma, or newline.
  This is the **passcode** (stage 6).
- `SECRET=<value>` — the same rule; this is the **secret word** (stage 7).

Note: the `SECRET=` value may appear at the very **end** of the note with no trailing comma,
and it may contain uppercase letters and digits. Handle both.

### 4. Decode base64-obfuscated filenames

Every file under `/app/workspace/encoded/` is **named** with a base64 (URL-safe alphabet,
`A–Z a–z 0–9 - _`, **no `=` padding**) encoding of its actual name. Decode each filename
(accept the unpadded base64) and write the decoded names, one per line, **sorted** (byte/lexicographic
order), to `/app/decoded_names.txt`. Names may contain spaces, uppercase, `-`, `_`, or digits.

### 5. Persist the secret word with normalization

`/app/name.txt` must contain **exactly** the secret word with the expected normalization: all
**lowercase**, **no trailing whitespace** and **no leading whitespace** (a single trailing
newline is fine). For example `SECRET=BETA-Rider` → `beta-rider`.

### 6. Run a crypto CLI over every file in the source tree

Use the installed command-line crypto tool `openssl` (`enc`) to encrypt **every file** in
`/app/workspace/src/`, creating an encrypted copy in `/app/encsrc/` **mirroring the tree**. The
passphrase used is the recovered **passcode** (stage 3). Convention:

```
openssl enc -aes-256-cbc -pbkdf2 -salt -pass pass:<passcode> \
    -in src,relpath -out /app/encsrc/<relpath>
```

- `relpath` is relative to `src/`, so `src/beta/audit.log` → `/app/encsrc/beta/audit.log`.
- **No file may be skipped**: nested files, dotfiles, empty files, files without extensions —
  encrypt them all to the exact same relative location.
- Do **not** create extra output files that do not correspond to a source file (the verifier
  checks the encsrc set equals the src set exactly).

The verifier independently decrypts each `/app/encsrc` file with the same passcode and
compares byte-for-byte with the original source file.

## Deliverable summary

After your work, the following must exist with these exact shapes.

1. `/app/attack.py` — executable, with `recover_key(encrypt: p) -> (k0,k1)` callable exported.
2. `/app/keys` — at least one line beginning `key=` followed by the 4-hex-digit key bytes in
   order `<k0><k1>` (lowercase hex). Example `key=e7ee`.
3. `/app/plaintexts.txt` — one plaintext line per ciphertext, exact.
4. `/app/name.txt` — the secret word, normalized lowercase, no surrounding whitespace.
5. `/app/encsrc/...` (the encrypted source tree) and `/app/decoded_names.txt` are your
   supporting outputs (still checked, but not part of the four top-level deliverables).

Run your tool with:

```
python3 /app/attack.py <scenario_dir> <out_dir>
```

It writes `keys`, `plaintexts.txt`, `name.txt`, `decoded_names.txt`, and an `encsrc/` tree to
`<out_dir>`. The final invocation you should perform (and that lands the deliverables) is:

```
python3 /app/attack.py /app/workspace /app
```

## What is checked (and must work for hidden scenarios too)

- `/app/keys` recovers the true keys — correct `key=` hex.
- `/app/plaintexts.txt` has every plaintext line exactly (no missing, no reorder).
- `/app/name.txt` is the fully isolated secret, normalized.
- `decoded_names.txt` decodes every base64 filename correctly.
- `encsrc/` covers **every** source file and each decrypts back to the source bytes.
- Your `attack.py` also gets re-run on fresh hidden scenario directories, where the oracle
  binary, keys, note, source tree, and filenames are all **different** — your tool must be
  generic, not hard-coded to these values.

## Constraints

- Work only under `/app`; never under `/tests` or `/solution` (you will not have access).
- Do not modify `/app/workspace` fixtures in a way that changes their meaning.
- The oracle binary `yonder_enc` and the cipher reference are read-only inputs.
- All deliverables must be produced by **running** your tool (not edited by hand), and your
  tool must work on **new** inputs.
