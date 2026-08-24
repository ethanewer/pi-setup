# Doom WAD file format: parsing the directory

Doom (id Software, 1993) stores its game data in **WAD** files ("Where's All
the Data?"). A WAD is a little-endian binary container with this layout:

```
offset 0   : 4 bytes magic   "IWAD" or "PWAD" (also "FWAD")
offset 4   : 4 bytes (LE)    number of lumps (directory entries) N
offset 8   : 4 bytes (LE)    byte offset where the directory starts
```

The **directory** is an array of `N` entries, each 16 bytes:

```
4 bytes (LE)  file position of the lump data
4 bytes (LE)  size of the lump in bytes
8 bytes       lump name (ASCII, null/space padded)
```

`/app/doom.wad` is a small, well-formed WAD file (an IWAD with 3 lumps).

## Task

Write a Python 3 script `/app/parse_wad.py` that reads `/app/doom.wad` and
writes `/app/wadinfo.txt` with exactly three lines:

```
TYPE IWAD
LUMPCOUNT 3
BIGGEST MAP01
```

- `TYPE` is the 4-byte magic string from the header.
- `LUMPCOUNT` is the number of directory entries.
- `BIGGEST` is the name of the lump with the **largest size**; if several
  lumps tie for the largest size, use the one that appears **first** in the
  directory. (Strip trailing null/space bytes from names.)

The verifier parses the same WAD file independently and compares all three
lines.