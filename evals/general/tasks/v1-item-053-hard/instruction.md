# Item-053 (hard) — Reassemble a deleted, fragmented PNG from a raw image

A second suspect image `/workspace/case.dd` contains a file `data/figure.png`
that was deleted, then its **data blocks were reordered by a defragmenter**.
Because the on-disk order no longer reflects the logical order, a naive
concatenation produces garbage. The volume journal records two competing
"allocations" for the same name — a **stale snapshot** and an
**authoritative/current** one — and you must determine which is real by forming
hypotheses from the filesystem metadata and validating your reconstruction.

Work on a copy if you like, but never modify the original image.

## Volume layout (verify against the bytes with `xxd` / a short python snippet)

All integers little-endian. Sector = 512 bytes.

- offset `0`: magic, 8 ASCII bytes `CASEIMG2`
- offset `8`: sector size, uint64
- offset `16`: directory offset, uint64

Directory: **128-byte records**, one per journal entry:

| offset | meaning |
|---|---|
| 0      | status: 0x10 allocated, 0xE5 deleted |
| 1      | journal marker: **0x01 = stale snapshot**, **0x55 = current/authoritative** |
| 5      | name length |
| 6..37  | name (NUL-padded) |
| 38..   | **4 extents**, each 16 bytes: `seq` uint32, `offset` uint64, `length` uint32 |

An extent describes one stored fragment: where it physically sits
(`offset`, `length`) and its position in the logical file (`seq`). A record's
fragments must be concatenated **in the order the record lists them**.

The stale snapshot lists the fragments in the defragmented (wrong) order; the
current record lists the true order. Only the current order yields a valid PNG
(bytes start `89 50 4E 47 0D 0A 1A 0A` and the file ends with an `IEND` chunk).

## Deliverables (in `/app`)

1. `/app/figure.png` — the correctly reassembled, byte-exact PNG.
2. `/app/figure.sha256` — lowercase hex SHA-256 of exactly `/app/figure.png`.
3. `/app/journal.json` — the audit record, exactly:
   ```json
   {
     "image": "/workspace/case.dd",
     "name": "data/figure.png",
     "status": "0xE5",
     "marker": "0x55",
     "extents": [
       {"seq": 1, "offset": <int>, "length": <int>},
       {"seq": 2, "offset": <int>, "length": <int>},
       {"seq": 3, "offset": <int>, "length": <int>},
       {"seq": 4, "offset": <int>, "length": <int>}
     ],
     "image_sha256": "<sha256 of unmodified case.dd>",
     "reassembled_sha256": "<sha256 of figure.png>"
   }
   ```

## Success criteria

- `/app/figure.png` is byte-identical to the reassembly produced from the
  current journal record (valid PNG, exact content).
- `/app/figure.sha256` matches.
- `/app/journal.json` records the authoritative marker (0x55), the true extent
  list in order, and both hashes; the on-disk image is unmodified.