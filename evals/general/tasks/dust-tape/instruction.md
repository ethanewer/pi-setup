# dust-tape — PDP-11 tape-archive triage

The **Harlow Retro-Computing Society** recovered a box of DECtape images. Before
anything can be emulated, every blob in the recovery dump must be triaged: which
files are machine code for the old 16-bit **PDP-11** architecture (classic
`a.out` format), which are ordinary host executables, and which are junk. You
must build the triage tool. Everything happens under `/app`.

The verifier will **re-run your program on hidden artifact sets** (other PDP-11
binaries with different headers, other ELF binaries, truncated files, text
files), so `/app/triage.py` must be a general header inspector — never hard-code
to the shipped files' bytes.

## Deliverables (both required)

1. `/app/triage.py` — an executable Python 3 program with this exact interface:
   ```
   python3 /app/triage.py <file>
   ```
   It inspects the file's raw bytes (it must **never execute** the file) and
   prints **exactly one JSON object on stdout** and nothing else. Exit `0` in
   every case below (only an unreadable/nonexistent file may exit nonzero).

2. `/app/inventory.json` — the triage of the **whole visible archive**: the JSON
   object produced by scanning every file in `/app/artifacts/` (see "Archive
   report" below).

## Classification contract

### Case 1 — legacy PDP-11 `a.out` (the interesting one)

The file begins with a 16-bit **little-endian** magic word whose value is one
of:

| magic    | variant name      |
|----------|-------------------|
| `0x0107` | `shared-text`     |
| `0x0108` | `pure-text`       |
| `0x0109` | `separate-i&d`    |
| `0x010B` | `overlay`         |

The PDP-11 `a.out` header is **eight consecutive 16-bit little-endian words**
(16 bytes total), in this order:

```
magic, tsize, dsize, bsize, symsize, entry, trsize, drsize
```

(`tsize`/`dsize`/`bsize` are text/data/bss byte sizes, `symsize` the symbol
table size, `entry` the entry point, `trsize`/`drsize` relocation-table sizes.)

For such a file the JSON object must contain:

```json
{
  "format": "a.out",
  "arch": "pdp11",
  "host_executable": false,
  "magic_hex": "0x0108",
  "variant": "pure-text",
  "tsize": 2592, "dsize": 384, "bsize": 64,
  "symsize": 544, "entry": 0, "trsize": 96, "drsize": 16,
  "mem_image": 3040,
  "note": "..."
}
```

- `magic_hex` is lowercase, 4 hex digits, `0x`-prefixed.
- `mem_image` = `tsize + dsize + bsize` (the memory footprint of the loadable
  image).
- `note` is any string that **mentions the PDP-11 architecture** (e.g.
  `"PDP-11 a.out; not runnable on this host"`).
- **Truncated header edge:** if the file's first word matches a magic above but
  the file is **shorter than 16 bytes**, still classify it as
  `format: "a.out"`, `arch: "pdp11"`, `host_executable: false`, with the correct
  `magic_hex`/`variant`; every header field that is not fully present in the
  file (`tsize` … `drsize`, `mem_image`) must be `null`. Do **not** crash.

### Case 2 — ELF (a normal-or-not host executable)

The file starts with the 4 bytes `7f 45 4c 46` (`\x7fELF`):

- If the file is **shorter than 20 bytes** (truncated header), output
  `format: "elf-truncated"`, `arch: "unknown"`, `host_executable: false`, all
  other fields `null`. Exit 0, no crash.
- Otherwise: `ei_class` (byte 4) is `1` → `format: "elf-32"`, `2` →
  `"elf-64"`, anything else → `"elf-?"`.
- `ei_data` (byte 5) selects the byte order for the 16-bit `e_machine` field at
  bytes 18–19: `1` → little-endian, `2` → big-endian.
- `arch` is a short name from this table of machine numbers:
  `3:x86, 62:x86_64, 40:arm, 183:aarch64, 8:mips, 20:powerpc, 21:powerpc64,
  243:riscv, 18:sparc, 5:m68k, 50:ia64`; any other value →
  `unknown-elf-machine-<N>` (decimal N).
- `host_executable` is `true` **only** for `x86_64` (this host's architecture);
  otherwise `false`.
- `magic_hex`/`variant`/all size fields are `null`.

### Case 3 — PE stub

First two bytes are `MZ`: `format: "pe"`, `arch: "x86-family"`,
`host_executable: false`, other fields `null`.

### Case 4 — anything else

`format: "unknown"`, `arch: "unknown"`, `host_executable: false`, other fields
`null` — except: if the blob is at least 8 bytes and **more than 90%** of its
bytes are printable ASCII (`0x20..0x7e`, plus newline `\n` and tab `\t`),
set `format: "text"` instead. An empty file is `"unknown"`.

### Shared requirements

- Every JSON object has exactly these keys: `format, arch, host_executable,
  magic_hex, variant, tsize, dsize, bsize, symsize, entry, trsize, drsize,
  mem_image, note`.
- `host_executable` is a JSON boolean; sizes are JSON integers (or `null`);
  `note` is always a string (empty string is fine where nothing applies).
- Never print anything to stdout except the one JSON object.

## Archive report (`/app/inventory.json`)

Scan the directory `/app/artifacts/` and write a JSON file of exactly this
shape:

```json
{
  "archive": { "<filename>": { ...classification object... }, ... },
  "pdp11_files": ["<name>", ...],
  "host_executable_files": ["<name>", ...]
}
```

- `archive` maps **every** file of `/app/artifacts/` (recursive; use paths
  relative to `/app/artifacts/`, e.g. `"tapes/old.pdp11"` if there were
  subdirectories — the shipped archive is flat) to its classification object,
  computed by the same rules as above.
- `pdp11_files`: sorted list of names whose classification has
  `arch == "pdp11"`.
- `host_executable_files`: sorted list of names whose classification has
  `host_executable == true`.

## Edge cases the hidden sets probe

- PDP-11 files with **different** magics and header values than the shipped
  ones (all four variants appear across visible + hidden sets).
- A **truncated** PDP-11 `a.out` (header shorter than 16 bytes) — must not
  crash, missing fields `null`.
- ELF files of both endiannesses, different classes, and unusual machines;
  a **truncated** ELF (< 20 bytes); the host `x86_64` case.
- `MZ` stubs, pure-text files, random binary junk, and an **empty file**.
- Do **not** modify anything in `/app/artifacts/`.

## Constraints

- Python 3 standard library only; no network at run or verify time.
- The verifier runs `python3 /app/triage.py <hidden artifact>` unchanged and
  re-checks `/app/inventory.json` against the shipped archive, so the program
  must be fully general.
