In `/app` there is a CSV file `leaderboard.csv` with a header row and columns `model`, `task_a`, `task_b`, `task_c`. Each row is an embedding model and its quality scores (0–100, higher is better) on three evaluation tasks.

Write a Python script `/app/leaderboard.py` that:

1. Reads the CSV.
2. For each model computes its **MTEB-averaged score** = mean of the three task scores, rounded to 2 decimals: `round((a+b+c)/3, 2)`. Use the standard library `csv` module.
3. Ranks models by that averaged score, **descending**. Ties are broken by original row order (a model earlier in the file ranks higher).
4. Writes `/app/mteb.json` as exactly:
```json
{"top_model": "<name of highest-ranked model>", "top_score": <its rounded average as a number>, "ranking": [["<name>", <avg>], ...]}
```
The `ranking` list is ordered from best (index 0) to worst.

Run the script so `/app/mteb.json` exists with the correct contents.