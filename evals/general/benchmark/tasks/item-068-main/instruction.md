# Largest file probe

`/app/filedir/` contains several plain-text files. Read the directory and find
the **file with the largest byte size** (the largest number of bytes, i.e. the
longest file on disk).

Write to `/app/answer.json` the name of that file:

```json
{
  "largest": "c.txt"
}
```

Compute the answer from the actual directory contents. If two files tie for
the largest size, report the one whose name sorts first (alphabetically). Use
`os.path.getsize` (or `stat -c %s`) on each entry.