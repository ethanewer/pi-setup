# Recognise archive formats

Three archive/compression files are present in `/app/`:

- `/app/arc_a.tar`
- `/app/arc_b.zip`
- `/app/arc_c.gz`

Each is one of these three formats:

- **tar** — a plain TAR (tape archive) container. Its entries are identified by the ASCII header block; the bytes at file offset **257** hold the magic string `ustar` (bytes `0x75 0x73 0x74 0x61 0x72`) for a standard "POSIX" tar header.
- **zip** — a ZIP archive. Its first 4 bytes are the local file header signature `PK\x03\x04` (`0x50 0x4b 0x03 0x04`).
- **gz** — a gzip-compressed stream. Its first 2 bytes are the gzip magic `\x1f\x8b` (decimal 31 139).

For each file, identify its format **by inspecting its magic bytes** (use the filename extension only as a hint, not as proof). Then write `/app/formats.json`:

```json
{
  "/app/arc_a.tar": "tar",
  "/app/arc_b.zip": "zip",
  "/app/arc_c.gz": "gz"
}
```

Map each absolute path to its format string using only these values: `"tar"`, `"zip"`, `"gz"`.