Assembly of DNA fragments — the "golden gate" overlap-merge idea — fuses fragments into a single longer string. When one fragment's **suffix** equals another fragment's **prefix**, the two overlap; merging them keeps the overlap only once (append the second fragment's non-overlapping tail).

`/app/fragments.txt` contains one fragment per line, in this order:

```
ABCDEF
DEFGH
GHIJK
```

Fuse all fragments into one shortest possible superstring by repeatedly applying the largest suffix→prefix overlap until a single string remains. The resulting string for this input is unique regardless of merge tie-breaking.

Write the final single assembled string (with nothing else) to `/app/assembled.txt`.

For example, `ABCDEF` and `DEFGH` share the 3-character overlap `DEF`, so fusing them yields `ABCDEFGH`. Continue in the same style with the remaining fragments. The verifier independently computes the fusion and compares it with `/app/assembled.txt`.