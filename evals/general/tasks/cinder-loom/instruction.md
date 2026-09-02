# Cinder Loom flash-store recovery

You are a forensic recovery engineer for the "Loom" photo kiosk line. A flash
store image was pulled from a bricked unit: its directory still lists entries,
but several of them were marked **deleted** while their payloads were never
erased. You must recover exactly the deleted, still-intact files and materialize
them byte-accurately into a clean directory. Everything below is exact:

- All offsets, field widths, flags, filenames and edge cases are authoritative.
- **Do not modify** `/app/store.img`.
- **Never read `/tests`** — it is not part of your workspace and is hidden.

## The Loom store format (`/app/store.img`)

```
offset 0   : 8 bytes  magic "LOOMSTR" followed by 0x01  (b"LOOMSTR\x01")
offset 8   : 2 bytes  u16 little-endian entry_count
offset 10  : `entry_count` directory entries packed back-to-back; each is:
    1 byte   flags      bit0 = DELETED (1) or ACTIVE (0)
                         bit1 = ROT    (1 = payload known to be clobbered)
    1 byte   name_len   length of the name bytes that follow
    name_len bytes      name  (ASCII, letters/digits/._-, no separators)
    4 bytes  u32 LE     data_offset  (absolute offset of the payload in the image)
    4 bytes  u32 LE     data_len
    4 bytes  u32 LE     crc32        CRC-32 (zlib) of the ORIGINAL payload bytes
```

- Payload blobs live at arbitrary (16-byte aligned) offsets elsewhere in the
  65536-byte image; they are NOT adjacent to the directory.
- Every byte outside the directory and the referenced payload regions is slack:
  `0x00`/`0xFF` padding plus **orphan ghost bytes** that belong to no directory
  entry. Slack bytes must never be recovered.
- The CRC-32 in an entry is always the CRC of the *original* payload. For an
  intact payload the on-image bytes still match; for a **rot** entry the on-image
  bytes were overwritten (CRC mismatch) — that payload is unrecoverable and must
  be skipped.
- An ACTIVE entry (bit0 = 0) is live data, not a recovery target; it must never
  appear in your output.

## Deliverables (both required)

| Path | Meaning |
|------|---------|
| `/app/carve.py` | your reusable recovery tool (spec below) |
| `/app/recovered/` | the recovered deleted files from `/app/store.img`, byte-exact, with **nothing else** in the directory |

`/app/carve.py` is invoked as:

```
python3 /app/carve.py <store_path> <outdir>
```

It must:

1. Parse the Loom store per the format above (count, then each variable-length
   directory record in order).
2. For every entry with bit0 (DELETED) set: read `data_len` bytes at
   `data_offset`, compute the zlib CRC-32, and compare with the stored CRC.
3. Recover (write the payload bytes byte-for-byte as `<outdir>/<name>`) exactly
   those deleted entries whose CRC matches. Skip rot entries (CRC mismatch).
4. The output directory must contain **exactly** the recovered files — if
   `outdir` already contains files, your tool must remove them first so stale
   artifacts cannot leak into the result. Create `outdir` if needed.
5. Print one line per recovered file: `RECOVERED <name>` (in directory order),
   and a final line `TOTAL=<n>`.
6. Work on **any** conforming Loom store: different entry counts, names, sizes,
   offsets, rot flags and ghost slack — the grader re-runs your tool on hidden
   stores, so no hard-coded filenames, offsets or byte counts.

## Your visible-case output

Run your tool on the provided store and leave the result in place:

```
python3 /app/carve.py /app/store.img /app/recovered
```

`/app/recovered/` must then contain exactly the deleted, intact files of
`/app/store.img` with byte-exact contents — no active files, no rot payloads,
no ghost slack, no helper or temp files.

## Hidden evaluation

The verifier runs `python3 /app/carve.py` unchanged on **hidden** stores
(different entry sets, different keys of everything above, including rot
entries and orphan slack) and byte-compares each recovered file against the
reference, plus checks that the output directory contains nothing extra.

## Constraints

- No network access; Python 3.12 standard library only.
- Do not modify `/app/store.img`.
- If all checks pass, the reward is 1.
