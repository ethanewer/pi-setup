# Writing a formatted text report

`/app/input.txt` is a UTF-8 plain-text file with **one record per line**, each
line of the form `<name> <score>` (a single space), where `name` is a lowercase
word and `score` is an integer. Example content:

```
alpha 12
bravo 7
charlie 2
delta 5
echo 9
foxtrot 3
```

Write a Python 3 script `/app/make_report.py` that reads `/app/input.txt`,
sorts the records by `name` in **ascending** order, and writes a plain-text
report to `/app/report.txt` with:

1. one line per record, preserving the original `<name> <score>` format, in
   sorted order;
2. a final line `TOTAL <sum of all scores>`.

For the file above the expected `/app/report.txt` is exactly:

```
alpha 12
bravo 7
charlie 2
delta 5
echo 9
foxtrot 3
TOTAL 38
```

Run the script so `/app/report.txt` exists. The verifier independently parses
`/app/input.txt`, sorts by name, and compares `/app/report.txt` line-for-line.