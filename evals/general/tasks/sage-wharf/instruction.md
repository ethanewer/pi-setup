# Grimwater Docks — forensic reconstruction

You are a digital forensics analyst. Investigators seized an onboard terminal
belonging to E. Quell, deputy harbormaster of Grimwater Docks, accused of
tampering with dock shipping records. A byte-for-byte forensic image was taken
and a working replicate placed in `/app/evidence/`. Everything below was found
on that terminal. Your job is to reconstruct the true contents of the artifacts.

## Deliverables

You must produce two artifacts in `/app/`:

1. **`/app/solve.py`** — a general-purpose command-line program (see the CLI
   contract below). It must work as a general tool, not just on the shipped
   evidence, because it will be re-run on new inputs of the same formats.
2. **`/app/answer.json`** — the reconstruction report produced from the
   evidence (`/app/evidence/`). Do not hand-write guessed values; your program
   must compute them (see the `solve-evidence` command).

You may use only the Python 3 standard library. `python3` is available. Do not
execute any recovered shell command — decode them, never run them.

## Evidence layout (`/app/evidence/`)

- `logbook.bin` — the deputy's log, stored using the range-coding format of §1.
- `sentries.bin` — a list of recovered command payloads, stored in the sentinel
  obfuscation format of §2.
- `harbor.db` — a SQLite database.
- `harbor.db-wal` — that database's write-ahead log, which has been obfuscated
  with a byte transform you must identify (§3).
- `.probe`, `.cache`, `marker` — names referenced by the recovered commands
  (path roots only; not files you need to read).

---

## §1. Range-coding format

The log is arithmetic-coded over a byte alphabet (symbols `0x00`..`0xFF`) with a
fixed frequency model:

- frequency of symbol `s` — `freq[s] = s + 1`
- cumulative frequency *before* symbol `s` — `cum[s] = s*(s+1)//2`
- total of the model — `TOTAL = 32896`

The stored file is:

```
[4-byte big-endian length N] [arithmetic-coded stream]
```

`N` is the number of plaintext bytes. The stream is produced/consumed by the
following 32-bit arithmetic coder (renormalize whenever the top byte of `low`
and `high` equal):

Encoder:
```
low = 0; high = 0xFFFFFFFF
for each byte b:
    rng = high - low + 1
    lo  = low + (cum[b]*rng)//TOTAL
    hi  = low + ((cum[b]+freq[b])*rng)//TOTAL - 1
    low, high = lo, hi
    while (low ^ high) & 0xFF000000 == 0:
        emit byte (low>>24)&0xFF
        low  = (low<<8)  & 0xFFFFFFFF
        high = ((high<<8)|0xFF) & 0xFFFFFFFF
finally emit the 4 bytes of `high`, most-significant byte first.
```

Decoder:
```
read N (4 bytes). read the next 4 bytes as `code` (MSB first).
low = 0; high = 0xFFFFFFFF
repeat N times:
    rng   = high - low + 1
    scaled = ((code - low + 1)*TOTAL - 1)//rng
    find the smallest s in 0..255 such that cum[s+1] > scaled
    emit byte s
    lo  = low + (cum[s]*rng)//TOTAL
    hi  = low + ((cum[s]+freq[s])*rng)//TOTAL - 1
    low, high = lo, hi
    while (low ^ high) & 0xFF000000 == 0:
        low  = (low<<8) & 0xFFFFFFFF
        high = ((high<<8)|0xFF) & 0xFFFFFFFF
        code = ((code<<8) | next_byte) & 0xFFFFFFFF
```

Notes / edge cases the hidden cases probe:
- Empty plaintext: `N = 0`; the file still has the 4-byte length plus the 4
  final `high` bytes. Decoding yields the empty byte string.
- Single-symbol inputs, runs of `0x00`, runs of `0xFF`, and arbitrary bytes in
  `0x00`..`0xFF` must all round-trip losslessly.
- The decoder must read exactly `N` symbols and stop; trailing bytes are ignored.

## §2. Sentinel command obfuscation

Each recovered command is a UTF-8 string `C`. The payload bytes for one command
are produced as:

1. reverse the string: `s1 = C[::-1]`
2. standard base64-encode: `s2 = base64.b64encode(s1.encode('utf-8'))`
3. XOR every byte of `s2` with the fixed key `0x2B`.

`sentries.bin` is a sequence of these payloads, each prefixed with a 4-byte
big-endian length, concatenated back to back:

```
[4-byte len][payload bytes]  [4-byte len][payload bytes]  ...
```

To recover: undo XOR with `0x2B`, base64-decode, reverse.

Edge cases the hidden cases probe: an empty command (payload length 0, recovered
string is empty), commands with mixed case/digits/punctuation, and long commands.

## §3. Database WAL transform detection

A native SQLite write-ahead log (`-wal`) begins with a 4-byte magic equal to
`0x377f0682` or `0x377f0683` (stored big-endian). The evidence `harbor.db-wal`
is *not* in native form: a single-byte XOR has been applied to every byte of the
file. You must identify the transform.

Detection rule (return a string):
- If the file is shorter than 8 bytes → return `NONE`.
- If the first 4 bytes already equal a WAL magic → return `NONE`.
- Otherwise, for each key `k` in `0..255`: if XORing the first 4 bytes by `k`
  yields a WAL magic, return `KEY=<k>`.
- If no key fits → return `NONE`.

Edge cases the hidden cases probe: a genuinely native WAL (`NONE`), a
XOR-transformed WAL (`KEY=<k>`), a file shorter than 8 bytes (`NONE`), and an
arbitrary binary blob that is not a WAL under any single-byte XOR (`NONE`).

## §4. Multi-step digest chain

Given plaintext bytes `P`, the final digest is:

```
h1 = sha256(P)
h2 = sha1(h1[:20])
h3 = md5(h1[12:28] + h2)
final = sha256(h3 + P).hexdigest()
```

That is: `sha256` of `P`; `sha1` of the first 20 bytes of `h1`; `md5` of the
concatenation of `h1[12:28]` with `h2`; then `sha256` of the concatenation of
`h3` with the **original** `P`, hex-encoded. Changing any truncation, ordering,
or algorithm changes the result. The empty input must also work.

---

## CLI contract for `/app/solve.py`

The program must accept these subcommands (each writes to stdout; `file` is a
filesystem path):

```
python3 /app/solve.py decode <file>          # range-decode file -> raw plaintext bytes
python3 /app/solve.py encode <file>          # range-encode file -> raw coded bytes
python3 /app/solve.py unobfuscate <file>     # recover the UTF-8 command from a payload
python3 /app/solve.py wal-report <file>      # print "NONE" or "KEY=<k>"
python3 /app/solve.py digest <file>          # print the §4 final hex digest
python3 /app/solve.py solve-evidence         # write /app/answer.json (see below)
```

`decode`, `encode` and `unobfuscate` write raw bytes/text with **no** added
trailing newline (consumers compare byte-for-byte). `wal-report` and `digest`
print a single line (a trailing newline is acceptable).

## `/app/answer.json`

`solve-evidence` must write `answer.json` with **exactly** these keys:

- `log_plaintext_hex`: the hex encoding (lowercase, no separators) of the
  decoded `logbook.bin` bytes.
- `secret`: the token on the line `secret = <token>` in the decoded logbook
  plaintext (the whole token as written, e.g. `quayside-9C2`).
- `sentinel_commands`: an array of the recovered command strings from
  `sentries.bin`, in file order.
- `wal_transform`: the string from §3 applied to `harbor.db-wal`
  (here `KEY=<k>`).
- `digest`: the §4 final digest of the decoded `logbook.bin` plaintext bytes.

Do not modify the evidence files or remove any other deliverable.
