# Cinder firmware recovery — reassemble the image from hexdump fragments

A firmware image was shredded into several `hexdump -C`-style **fragment files**
and the binary itself was destroyed. Reassemble the original image from the
dumps so it can be inspected and executed as a real program again.

You work under `/app`. The fragments live in `/app/dumps/`.

## The dump format (exactly as specified here)

Every fragment file is plain text whose lines are one of:

1. **Data line**
   ```
   OOOOOOOO  HH HH HH HH HH HH HH HH  HH HH HH HH HH HH HH HH  |AAAAAAAAAAAAAAAA|
   ```
   - `OOOOOOOO` — 8 lowercase hex digits: the **absolute byte offset** of the
     first byte of this row within the original image (rows continue the
     absolute numbering, they never restart at 0 inside a fragment).
   - Two spaces, then the row's bytes as two-digit lowercase hex pairs,
     separated by single spaces; there are **two** spaces between byte 8 and
     byte 9. Rows hold up to 16 bytes. A short final row right-pads the hex
     area with spaces.
   - One space, then `|`, an ASCII rendering (non-printable bytes shown as
     `.`), and `|`. The ASCII column is a convenience only — the hex pairs are
     authoritative.
2. **Repeat line**: a single `*`. It means the row immediately above the `*`
   repeats back-to-back (each a full 16-byte row at advancing offsets) up to
   (but not including) the offset of the next data line or the final
   offset-only line. You must **expand** these repeats; skipping them loses
   bytes.
3. **Offset-only line**: exactly 8 hex digits. No bytes; it terminates a repeat
   run and marks the end of a fragment.

A fragment's rows are strictly increasing in offset. The set of fragments in a
case **covers the whole image** (offsets 0 .. size-1, every offset present in
exactly one fragment, except where fragments deliberately overlap — overlapping
bytes are always identical). The last row of a fragment may be partial (fewer
than 16 bytes), and the final row of the image may be a single byte.

`/app/dumps/manifest.txt` lists the fragment filenames, one per line, in
**arbitrary order** — the absolute offsets, not the manifest order, determine
placement. Any `.hex` file in the directory **not** listed in the manifest is a
decoy and must be ignored.

## Deliverables

1. **`/app/solve.py`** — a reusable reassembler:

   ```
   python3 /app/solve.py <dumps_dir> <out_bin>
   ```

   Given any dumps directory with this layout (manifest + fragment files, the
   format above), it writes the reassembled image to `<out_bin>`, byte-exact.

2. **`/app/recovered.bin`** — the reassembly of `/app/dumps`, produced by
   running your program:

   ```
   python3 /app/solve.py /app/dumps /app/recovered.bin
   ```

   The result must be byte-exact (its SHA-256 is checked against the reference
   value computed from the pristine image), and it is a **real x86-64 ELF
   executable**.

3. **`/app/recovered_out.txt`** — run the recovered artifact and capture its
   stdout:

   ```
   chmod +x /app/recovered.bin
   /app/recovered.bin > /app/recovered_out.txt
   ```

   The artifact prints exactly one line; capture it verbatim (bytes, no extra
   whitespace). This proves the reassembly is a genuine, runnable executable.

## Grading (hidden inputs)

The verifier re-runs `/app/solve.py` on fresh hidden dumps directories you have
never seen. Hidden cases probe, among others:

- fragments listed in a shuffled manifest, plus a **decoy** fragment file not
  listed in the manifest (must be ignored);
- **overlapping** fragments whose overlapping bytes agree;
- fragments that make **heavy use of `*` repeat lines** (large runs of
  identical rows);
- a fragment whose **last row is a single byte** / partial rows;
- fragments with no `*` lines at all.

For each case the reassembled image must match the reference SHA-256 exactly,
must be an ELF executable, and running it must print the expected line.

## Constraints

- Python 3.12 standard library only; no network.
- Do not modify anything under `/app/dumps`.
- Do not read `/tests` or `/solution`.
