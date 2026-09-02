# FASTA record statistics

`/app/data.fasta` contains a FASTA file (text). Its format is:

- A record starts with a line whose first character is `>`, immediately followed
  by the record identifier (the rest of that line, up to the end of line; this
  is the record's full id string).
- The next line(s) belong to that record's sequence until the next `>` line.
  Sequence characters are uppercase letters only (whitespace should be ignored
  when computing length, but there is none here).

The file has exactly 5 records:

```
>alpha
ACGTGGTACCT
>beta
TTGAAACCTA
>delta_04
AATTGGTTA
>gamma
CCGTTATTCCAACCGG
>epsilon
GGCCAATTAACCGG
```

## Your task

Write a Python 3 script `/app/fasta_stats.py` that reads `/app/data.fasta` and
writes `/app/stats.json` containing exactly:

```json
{
  "num_records": 5,
  "total_length": <int: total number of sequence characters across all records>,
  "longest_id": "<id string of the record with the longest sequence>",
  "longest_len": <int: length of that longest sequence>
}
```

If two records tie for longest, use the one that appears first in the file.

Then run the script so `/app/stats.json` exists. The verifier parses the same
file independently and checks the JSON.