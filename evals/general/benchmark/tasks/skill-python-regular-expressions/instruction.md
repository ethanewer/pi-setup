# Python regular expressions (groups + substitution)

`/app/dates.txt` is plain text that contains ISO-style dates in the form `YYYY-MM-DD`.

Write `/app/rewrite_dates.py` that reads the file and uses the **`re` module with named groups** to:
- find every 4-digit year, 2-digit month, and 2-digit day matching the pattern `YYYY-MM-DD`
- rewrite each matched date into US format `MM/DD/YYYY` (month, slash, day, slash, year)
- preserve all surrounding text exactly (only the date tokens themselves change)
- write the fully rewritten text to `/app/rewritten.txt`.

Run the script so `/app/rewritten.txt` is produced. Deterministic expectations: every date in the file must be reformatted, and non-date text must be untouched.
