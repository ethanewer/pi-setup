# Regex pattern matching (Python `re`)

`/app/colors.txt` is plain text describing colors in hex form. Your task is to use the standard `re` module to find every color token.

A **color token** is defined as a literal `#` followed immediately by exactly **6 hex digits** (`0-9`, `a-f`, `A-F`). Only whole 6-digit groups count — for example `#FF3F00` is a valid color, but `#12AB` (4 digits) and `#12345` (5 digits) are not.

Write `/app/find_colors.py` that:
- reads `/app/colors.txt`
- uses a Python regular expression to extract all valid 6-digit color tokens (just the 6 hex digits, no `#`)
- computes the sum of their integer values interpreting each token as a base-16 number (e.g. `FF3F00` → `0xFF3F00`)
- writes that integer sum as a bare decimal to `/app/answer.txt`.

Run the script so `/app/answer.txt` is produced. The expected colors present are `FF3F00`, `12AB34`, `000000`, `FFFFFF`.
