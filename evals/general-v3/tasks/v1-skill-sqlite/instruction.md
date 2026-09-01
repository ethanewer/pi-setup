# SQLite

Create a SQLite database at `/app/books.db` **from scratch** using Python's built-in `sqlite3` module (no third-party packages needed).

## 1. Schema and data

Create two tables with these exact names and columns:

- `authors(id INTEGER PRIMARY KEY, name TEXT)`
- `books(id INTEGER PRIMARY KEY, title TEXT, author_id INTEGER, year INTEGER)`

Insert exactly these rows:

```
authors: (1, 'tolkien'), (2, 'asimov'), (3, 'le guin')
books:
  (1, 'The Hobbit',           1, 1937)
  (2, 'The Return of the King', 1, 1955)
  (3, 'I, Robot',             2, 1950)
  (4, 'Foundation',           2, 1951)
  (5, 'A Wizard of Earthsea', 3, 1968)
```

## 2. Analytic query

Write a Python script `/app/build_db.py` that:

1. Creates `/app/books.db` with the schema above and inserts the data (commit your changes).
2. Runs the following **JOIN + GROUP BY** aggregation against the database:

```sql
SELECT a.name, COUNT(b.id), MIN(b.year)
FROM authors a JOIN books b ON b.author_id = a.id
GROUP BY a.id
ORDER BY a.id;
```

3. Writes the result rows to `/app/result.txt`, one row per line, formatted as:

```
<author_name>:<count>:<min_year>
```

e.g. the line for `tolkien` is `tolkien:2:1937`.

Then run `/app/build_db.py` so that **both** `/app/books.db` and `/app/result.txt` exist.

## Verification

The verifier opens `/app/books.db`, runs the exact query above, and requires `/app/result.txt` to contain exactly those rows in that order (tolerating trailing whitespace / CRLF).