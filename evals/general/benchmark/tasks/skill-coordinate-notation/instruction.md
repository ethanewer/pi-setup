`/app/coords.txt` contains geographic coordinates, one coordinate per line. Each line is a single latitude or longitude in **DMS** form, using degree/minutes/seconds notation with a hemisphere letter. Example line:
```
40°26'46"N
```

A DMS value is written as `<degrees>°<minutes>'<seconds>"<hemisphere>` where `<hemisphere>` is exactly one of `N`, `S`, `E`, `W`.

Write a program `/app/convert.py` that:
1. reads every line of `/app/coords.txt` (each line is one DMS coordinate),
2. parses each into a signed decimal-degrees float:
   - decimal = degrees + minutes/60 + seconds/3600,
   - negate if the hemisphere is `S` (for latitude) or `W` (for longitude); leave positive for `N`/`E`,
   - example: `40°26'46"N` → `40.446111` (rounded to 6 decimals).
3. writes to `/app/decimal.txt` one decimal per line, each rounded to 6 decimal places.

Run `/app/convert.py` so `/app/decimal.txt` is produced. The verifier parses the same `coords.txt` independently and compares the rounded decimal values within tolerance.