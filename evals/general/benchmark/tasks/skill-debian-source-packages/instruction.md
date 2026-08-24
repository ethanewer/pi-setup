At `/app/debian-sources.list` there is a Debian-style **package source descriptor** file. It contains one or more package records. Records are separated by a blank line, and within a record each field is a line of the form `Key: value` (with one space after the colon). Every record has the fields `Name`, `Version`, and `Priority` (an integer, lower means higher precedence).

For example:
```
Name: zlib
Version: 1.2.13
Priority: 3
```

Write `/app/parse_sources.py` that:
1. reads `/app/debian-sources.list`,
2. parses every package source record,
3. sorts the records by `Priority` **ascending** (ties are broken by `Name` ascending),
4. writes to `/app/packages.json` a JSON array of objects `{"name": ..., "version": ...}` in that sorted order (no `Priority` field in the output).

For the provided file the expected output order (by priority) is: `ffmpeg`(1), `gtk`(2), `zlib`(3), `libpng`(4). Use only the Python standard library. Run your script so `/app/packages.json` exists.
