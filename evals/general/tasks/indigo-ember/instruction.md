# Relay-station logbook recovery

A beacon-relay station left an encrypted logbook behind. Everything you need is
in `/app/station`. You must build **one reusable Python tool**, `/app/recover.py`,
that decodes the operator's cryptogram, unlocks the station key, and decrypts
the whole ciphertext bundle — then run it on `/app/station` so the deliverables
exist under `/app`.

## Provided scenario contents (`/app/station/`, read-only — do not modify)

- `cipher_ref.py` — reference implementation of the **beacon relay cipher**.
  The key is **not** in this file.
- `cryptogram.txt` — an operator note that was letter-substituted.
- `clue.json` — the clued substitution mapping used to decode the note.
- `keybox.enc` — an OpenSSL-encrypted key box. Decrypting it with the note's
  passcode yields one line `key=<4 lowercase hex digits>` (the 16-bit cipher key).
- `ciphertexts.txt` — the logbook ciphertext. Each line is a 4-hex-digit
  16-bit block; each block encodes **two consecutive ASCII characters** of the
  payload, big-endian (first char in the high byte).

## The beacon relay cipher (16-bit block, 16-bit key)

One round is an ARX step; the cipher is exactly **four** rounds:

```
s = p & 0xFFFF
repeat 4 times:
    s = s XOR k                       (16-bit)
    s = rotl16(s, 3)                  ((s << 3 | s >> 13) & 0xFFFF)
    s = (s + 0x7A3B) & 0xFFFF
ciphertext = s
```

Decryption inverts each step in reverse order (subtract, rotr 3, XOR).
`cipher_ref.py` provides `enc_block`/`dec_block`.

## The tool contract

`/app/recover.py` must be runnable as:

```
python3 /app/recover.py <scenario_dir> <out_dir>
```

It must work on **any** scenario directory holding the five files above (the
hidden scenarios use different notes, mappings, passcodes, keys, and payloads),
and must write into `<out_dir>`:

1. `key.txt` — exactly one line `key=<4 lowercase hex digits>` (a trailing
   newline is fine).
2. `plaintexts.txt` — **one decrypted block per ciphertext line**, in the same
   order, each line being the block's **two ASCII characters**. Do not skip,
   reorder, or merge lines; the number of lines must equal the number of
   ciphertext lines.

The module must also export these two top-level functions (the grader imports
and calls them directly):

```python
def decode_cryptogram(text: str, clue: dict) -> str
def extract_passcode(note: str) -> str
```

### `decode_cryptogram(text, clue)`

`clue` is a JSON object of the shape:

```json
{"kind": "operator-note",
 "plain_alphabet": "abcdefghijklmnopqrstuvwxyz",
 "cipher_alphabet": "<26 distinct lowercase letters>"}
```

`cipher_alphabet[i]` is the encoded (ciphertext) letter standing for the plain
letter `plain_alphabet[i]`. Apply it to **every** character of `text`:

- letters are decoded via the mapping, **case-insensitively**, but the original
  case of the character is **preserved** (an encoded `Q` decodes to the
  uppercase form of the mapped plain letter);
- digits, punctuation, spaces, hyphens, and any other non-letter characters are
  copied through unchanged.

### `extract_passcode(note)`

`note` is the **decoded** note text. It contains a field written exactly as
`PASS=`. The passcode is the value immediately after `PASS=`; it ends at the
first space, comma, newline, or the end of the note — whichever comes first
(so a passcode at the very end with no trailing punctuation must still be
captured, and it may contain uppercase letters, digits, and hyphens). Return
the passcode as a string. If `PASS=` is present but nothing follows it, return
the empty string. Notes may contain decoy tokens such as `PASSKEY=`; only the
exact token `PASS=` starts the passcode.

## Deliverables (all required)

1. `/app/recover.py` — the reusable tool described above.
2. `/app/key.txt` — the recovered station key, produced by **running**
   `python3 /app/recover.py /app/station /app`.
3. `/app/plaintexts.txt` — the decrypted blocks, one per line, from the same run.

All deliverables must be produced by running your tool — do not hand-edit them.

## Edge cases the grader probes with hidden scenarios

- Notes where the `PASS=` value sits at the **very end** with no trailing
  punctuation, and notes with punctuation/commas after it.
- Passcodes containing digits, hyphens, and uppercase letters.
- Clue mappings that are **not** simple rotations; uppercase letters in the
  cryptogram that must stay uppercase after decoding.
- Ciphertext bundles of **different lengths** (2, 8, 30+ blocks); every block
  must be decrypted and written — a missing or extra line fails the check.
- Keys spanning the full 16-bit range (including values like `0x00A7` and
  `0xFF08`, always written as 4 lowercase hex digits).
- The payload may end with a padding space character.

## Constraints

- Work only under `/app`; never read `/tests` or `/solution`.
- Do not modify anything under `/app/station`.
- No network access. Standard library plus the `openssl` CLI are available.
- The grader re-runs `/app/recover.py` unchanged on fresh hidden scenario
  directories, so nothing may be hard-coded to the visible values.
