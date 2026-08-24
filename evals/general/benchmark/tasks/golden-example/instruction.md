In `/app` there is a CSV file `data.csv` with a header row and numeric columns `id`, `name`, `score`.

Write a script `/app/summarize.py` that reads `/app/data.csv` and writes `/app/summary.json` containing exactly:

```json
{"rows": <number of data rows>, "mean_score": <mean of the score column, rounded to 2 decimals>}
```

Then run the script so that `/app/summary.json` exists with the correct contents.
