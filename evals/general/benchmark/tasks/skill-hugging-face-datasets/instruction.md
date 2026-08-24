`/app/data.jsonl` is a JSON Lines file with dataset records. Each line is a JSON object with fields `id` (int), `text` (string), and `quality` (string, either `good` or `bad`).

Use the **Hugging Face `datasets` library** to load and filter it.

Write `/app/filter.py`, which:
1. loads the JSON Lines file into a `datasets.Dataset` using `load_dataset("json", data_files="/app/data.jsonl")`,
2. keeps only the rows whose `quality` is exactly `"good"`,
3. writes the number of kept rows (as an integer string) to `/app/count.txt`.

The file `/app/data.jsonl` is:
```
{"id":1,"text":"great day","quality":"good"}
{"id":"2","text":"terrible","quality":"bad"}
{"id":"3","text":"fine","quality":"good"}
{"id":"4","text":"horrid","quality":"bad"}
{"id":"5","text":"awesome","quality":"good"}
```

Run `/app/filter.py` so `/app/count.txt` is produced. There are exactly 3 `good` rows. The verifier does the same filtering with the same library.