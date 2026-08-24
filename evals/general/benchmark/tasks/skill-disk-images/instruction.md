# Disk images: parsing a FAT boot sector

`/app/floppy.img` is a raw disk image (a 1.44 MB floppy disk image, little-endian
throughout). Its first sector (bytes `0..511`) is a standard **FAT boot
sector** whose BIOS Parameter Block (BPB) fields live at these fixed offsets:

| Offset | Size | Field | Notes |
|-------:|-----|-------|-------|
| 11 | 2 (LE) | bytes per sector | `512` here |
| 13 | 1 | sectors per cluster | |
| 14 | 2 (LE) | reserved sectors | |
| 16 | 1 | number of FATs | |
| 17 | 2 (LE) | root directory entries | `224` here |
| 19 | 2 (LE) | total sectors | |
| 22 | 2 (LE) | sectors per FAT | |
| 43 | 11 (ASCII) | volume label | null-padded string, e.g. `DISKIMG26` |

A (possibly zero-padded) 11-byte label like `DISKIMG26\0\0\0` should be read by
stripping trailing `\0` and spaces.

## Task

Write a Python 3 script `/app/parse_boot.py` that reads `/app/floppy.img`,
decodes the BPB fields above, and writes `/app/fsinfo.txt` with exactly these
lines:

```
BYTES_PER_SECTOR 512
SECTORS_PER_CLUSTER 1
TOTAL_SECTORS 2880
SECTORS_PER_FAT 9
ROOT_ENTRIES 224
LABEL DISKIMG26
SIZE_OK true
```

The last line is a sanity check you compute from the parsed values: `true` if
the physical file length equals `BYTES_PER_SECTOR * TOTAL_SECTORS` bytes,
otherwise `false`. (Everything numeric should be written as a plain decimal
integer, and the label exactly as decoded.)

The verifier decodes the same fields from the image independently and compares
every line.