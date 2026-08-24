# Regex substitution with capture groups

`/app/data.txt` contains lines of the form `First Last YYYY`:

```
Alice Smith 1998
Bob Carter 2002
Carol Evans 1995
```

Write `/app/rewrite.py` that uses a **single `re.sub`** with **capture groups** to rewrite
each line `First Last Year` into the form `Last First born Year`, and writes the result
to `/app/result.txt` (one line per input line).

The regex should capture `(\w+)` (First), `(\w+)` (Last), and `(\d{4})` (Year), then
substitute with the backreference pattern `\2 \1 born \3`. Apply it to every non-empty
line; preserve line order.

Expected output:

```
Smith Alice born 1998
Carter Bob born 2002
Evans Carol born 1995
```

Run `python3 /app/rewrite.py` so `/app/result.txt` is produced. The verifier applies the
same regex to `data.txt` and compares byte-for-byte. Do not hardcode the output.