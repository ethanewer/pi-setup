`/app/page.html` is an HTML document containing a catalog table. Use Python's standard-library **`html.parser.HTMLParser`** (no external packages) to parse it.

Write `/app/parse.py`, which:
1. reads `/app/page.html` as text,
2. extracts the data rows from the `<table id="items">` table (its first row is the header row and must be skipped),
3. writes `/app/items.json` as a JSON list of objects, in row order:
   `{"name": "<string>", "qty": <int>, "price": <float>}`

The table columns are exactly `name`, `qty`, `price`. Every data row has all three cells. There are no nested tables and no character entities in the cell text.

Run `/app/parse.py` so `/app/items.json` is produced.

The file `/app/page.html` is:

```html
<html><head><title>Catalog</title></head><body>
<table id="items">
<tr><th>name</th><th>qty</th><th>price</th></tr>
<tr><td>apple</td><td>3</td><td>1.25</td></tr>
<tr><td>banana</td><td>5</td><td>0.50</td></tr>
<tr><td>cherry</td><td>2</td><td>2.50</td></tr>
</table>
</body></html>
```

The verifier parses the same file with the same library and compares `/app/items.json`.