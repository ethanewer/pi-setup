# R data processing

`/app/stats.csv` is a small CSV with a header row and two columns: `group` (a single uppercase letter) and `value` (an integer).

Write an **R script** `/app/summarize.R` that reads `/app/stats.csv`, computes the **mean** of the `value` column for each distinct `group`, and writes `/app/summary.csv` with a header row `group,value` followed by one row per group sorted by group name ascending. Report each mean rounded to 2 decimal places (e.g. `12`, `5`, `9`; use two decimals like `12.00` only where needed — use plain formatting of the rounded number).

Run the script (e.g. via `Rscript`/`R`) so `/app/summary.csv` is produced. Use base R (data.frame, split/sapply or a simple loop); no additional packages are required. The means are deterministic.
