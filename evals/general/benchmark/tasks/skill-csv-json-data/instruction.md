At `/app/data.csv` there is a comma-separated file with a header row. The first column is `id`, then `name`, then `role`, then `years`.

Write `/app/convert.py` that reads `/app/data.csv`, parses it as CSV, converts the `years` column to an integer, and writes the result as a JSON array of row objects to `/app/output.json`.

`/app/output.json` must be exactly the JSON encoding of a list of dicts:
```json
[
  {"id": "1", "name": "Ada", "role": "Engineer", "years": 5},
  {"id": "2", "name": "Grace", "role": "Engineer", "years": 8},
  {"id": "3", "name": "Linus", "role": "Mathematician", "years": 3},
  {"id": "4", "name": "Alan", "role": "Cryptographer", "years": 6}
]
```
The order of dicts must match the row order in the CSV. Use only the Python standard library (`csv` and `json`).

Run your program so the file is created. The verifier loads `/app/output.json` and compares it to the expected array.