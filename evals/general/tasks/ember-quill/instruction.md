# Quill snapshot appliance — recover deleted files

You are a storage forensics engineer. A cleanup job on the "Quill" snapshot
appliance deleted several operator files, but a pre-cleanup **raw block image**
survives at `/app/quill.img`. The image uses the documented **QSFS** flat
snapshot format below. Deleted-file inode records are still present (marked
deleted), alongside stale/corrupt inode copies and garbage. You must write a
**general carving tool** and use it to materialize the deleted files
byte-exactly into a clean directory.

- All offsets, field layouts, selection rules and edge cases below are
  **authoritative**.
- **Do not modify** `/app/quill.img`.
- **Never read `/tests`** — it is not part of your workspace and is hidden.

## Deliverables (all required)

| Path | Meaning |
|------|---------|
| `/app/carve.py` | your general recovery tool (run with `python3`), implementing the `recover` subcommand below — it must work on **any** QSFS image, not just this one |
| `/app/recovered/` | the deleted files carved from `/app/quill.img`, byte-exact, and **nothing else** |
| `/app/report.json` | JSON report of what was recovered (schema below) |

The evaluation re-runs `/app/carve.py` on **hidden** QSFS images (different
files, different decoys, different garbage), so the tool must be generic.

## QSFS image format (little-endian everywhere)

The image is a sequence of bytes; `u32` means unsigned 32-bit little-endian.

**Superblock** at byte offset 0, 512 bytes:

| offset | size | field |
|--------|------|-------|
| 0   | 4  | magic = ASCII `QSF1` |
| 4   | 4  | `block_size` (multiple of 512, >= 512) |
| 8   | 4  | `inode_area_block` (block index where inode slots start) |
| 12  | 4  | `inode_count` (number of inode slots) |
| 16  | 4  | `extent_area_block` (block index where extent records start) |

**Inode slots**: `inode_count` slots of exactly **128 bytes** each, starting at
byte offset `inode_area_block * block_size`, slot `i` at
`inode_area_block * block_size + i * 128`:

| offset | size | field |
|--------|------|-------|
| 0   | 4   | magic = ASCII `QINO` (anything else: empty/garbage slot — skip it) |
| 4   | 4   | `version` (u32, >= 1) |
| 8   | 4   | `flags` (u32; bit 0 set = **DELETED**) |
| 12  | 4   | `name_len` (u32, 1..96) |
| 16  | 96  | `name` bytes (UTF-8, not NUL-terminated; a flat filename, never contains `/`) |
| 112 | 4   | `content_size` (u32, exact file size in bytes) |
| 116 | 4   | `extent_start` (u32, index of the first extent record) |
| 120 | 4   | `extent_count` (u32, number of extent records; may be 0) |
| 124 | 4   | `crc32` (u32, IEEE CRC-32, i.e. `zlib.crc32`, of the exact content bytes) |

Unused bytes inside a slot are zero.

**Extent records**: 8 bytes each, at byte offset
`extent_area_block * block_size + k * 8` for record index `k`:

| offset | size | field |
|--------|------|-------|
| 0 | 4 | `byte_offset` (absolute byte offset into the image) |
| 4 | 4 | `byte_length` (length in bytes; never 0) |

The content of a file is the concatenation of its `extent_count` consecutive
extent records (indices `extent_start` .. `extent_start+extent_count-1`), each
read from `img[byte_offset : byte_offset + byte_length]`.

## Recovery selection rules (exactly these)

1. Only inode slots whose magic is `QINO` are candidates; skip anything else.
2. Skip a candidate whose extent records are out of the image bounds, whose
   extent lengths sum to something other than `content_size`, or whose CRC-32
   of the assembled content does not equal the stored `crc32` — such slots are
   **stale/corrupt copies** and must never be recovered.
3. Of the remaining candidates, only those with the **DELETED** flag
   (`flags & 1`) are recovered. Live files (flag bit 0 clear) are **never**
   recovered, even if a live file shares a name with a deleted one.
4. Among deleted, valid candidates with the **same name**, recover the one
   with the **highest `version`**.
5. Write each recovered file byte-exact under its name into the output
   directory. A deleted file with `content_size == 0` (no extents) must still
   be created as an **empty file**.
6. The output directory must end up containing **only** the recovered files.

## `/app/carve.py` interface

```
python3 /app/carve.py recover <image> <outdir> [report_json]
```

- Recovers deleted files from `<image>` into `<outdir>` (create the directory
  if needed) per the rules above.
- If `[report_json]` is given, also write a JSON object mapping each recovered
  filename to `{"size": <int bytes>, "version": <int>, "sha256": <lowercase
  hex sha256 of the recovered bytes>}`, keys sorted.
- It must work on **any** conforming QSFS image (different block geometry,
  counts, garbage, decoys, names). Standard library only.

## Required visible outputs

Run your tool on the provided image:

```
python3 /app/carve.py recover /app/quill.img /app/recovered /app/report.json
```

- `/app/recovered/` must contain exactly the deleted files recovered from
  `/app/quill.img`, byte-exact, and nothing else.
- `/app/report.json` must be the report for that same run.

## Hidden evaluation

The verifier runs `python3 /app/carve.py recover <hidden_image> <tmpdir>` on
at least two hidden QSFS images and byte-compares every file in the output
directory (and the set of filenames) against the reference recovery. Decoy
inodes in the hidden images include stale lower versions, higher versions with
bad CRC, size/extent inconsistencies, live files, and pure garbage slots —
the selection rules above decide everything. If your tool hard-codes names,
offsets or file counts it will fail.

If all deliverables are correct and every check passes, the reward is 1.
