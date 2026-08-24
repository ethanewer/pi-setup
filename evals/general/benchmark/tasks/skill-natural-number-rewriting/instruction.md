In `/app` there is a file `numbers.txt` containing natural-number rewriting tasks. Each line has three space-separated fields:

```
<value> <from_base> <to_base>
```

- `<value>` is written in base `from_base` (with no leading sign; it is a non-negative natural number).
- `from_base` and `to_base` are each one of `2`, `10`, `16` (binary, decimal, hexadecimal).
- Digits use lowercase letters for `a`–`f` in hexadecimal.

Write a Python script `/app/rewrite.py` that:

1. Reads every non-empty line of `numbers.txt`.
2. For each line, interprets `value` as a natural number in base `from_base`, converts it to base `to_base`, and formats the result **without any base prefix** (no `0b`, `0o`, or `0x`) and without leading zeros (the value `0` is written as `0`).
3. Writes `/app/converted.txt` with one converted value per line, in the same order as the input lines.

For example, the line `1010 2 10` means "the binary string 1010, converted to decimal", so the output value would be `10`.

Run the script so `/app/converted.txt` exists with the correct contents.