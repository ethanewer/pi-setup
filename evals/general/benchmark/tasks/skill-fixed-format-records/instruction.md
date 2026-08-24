In `/app` there is a file `/app/people.dat` containing **fixed-width records** (no delimiters). Every record is exactly **29 characters** and consists of four fields:

- `id`   : columns 0..3  (4 chars, numeric, zero-padded on the left, e.g. `0001`)
- `name` : columns 4..15 (12 chars, left-aligned, space-padded)
- `age`  : columns 16..18 (3 chars, numeric, space-padded on the left)
- `city` : columns 19..28 (10 chars, left-aligned, space-padded)

Each record is terminated by a newline. The file contains exactly 3 records.

Write a script `/app/parse.py` that reads `/app/people.dat`, parses each record into a dictionary with keys `id` (int), `name` (str, trimmed of padding), `age` (int), and `city` (str, trimmed of padding), and writes `/app/records.json` containing a JSON list of these dictionaries, e.g.:
```json
[{"id": 1, "name": "Alice", "age": 30, "city": "New York"}]
```

Run your script so that `/app/records.json` contains the correct parsed records. Use `python3`.