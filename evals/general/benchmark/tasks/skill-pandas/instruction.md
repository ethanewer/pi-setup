# Grouped aggregate with pandas

`/app/data.csv` is a CSV file with a header row and three columns: `id`, `region`,
and `amount`. The `amount` column contains integers.

Use the **pandas** library to load this file, group the rows by the `region` column,
and compute the **sum** of `amount` for each region.

Then sort the regions by their summed amount in **descending order** (largest total
first). Regions with distinct totals are guaranteed.

Write the result to `/app/summary.csv` as a CSV file with exactly this header row:

```
region,total
```

followed by one line per region with the region name and its summed amount as an
integer, separated by a comma (no spaces). The order of lines must be by descending
total (largest total on line 2, second largest on line 3, and so on).

Example of the expected shape (numbers are illustrative only):

```
region,total
south,65
west,43
```

Finish by confirming the file exists and contains exactly 4 data rows (one per region).
