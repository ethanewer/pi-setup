# Modern Python 3 features: dataclasses and f-strings

`/app/records.txt` contains one record per line:

```
alice 10
bob 20
carol 30
dave 40
```

Each line is `name value` separated by a single space; `value` is an integer.

Write a Python program `/app/report.py` written in modern **Python 3** that uses:

- the `@dataclass` decorator (from `dataclasses`), and
- **f-string** formatting.

Do the following:

1. Define a dataclass `Record` with fields `name: str` and `value: int`.
2. Read `/app/records.txt`, parse every line into a `Record`.
3. Compute `mean` = sum of all `value`s divided by the number of records.
4. Write `/app/report.txt` with one line per record in **file order** with format `{name}={value}`, then a final line `mean={mean:.2f}` (exactly two decimals), e.g.:

```
alice=10
bob=20
carol=30
dave=40
mean=25.00
```

Then run `/app/report.py` so `/app/report.txt` exists. The verifier recomputes the expected report from `/app/records.txt` and requires an exact match (line order included).