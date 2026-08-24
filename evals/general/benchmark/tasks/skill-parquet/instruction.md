# Apache Parquet conversion

`/app/data.csv` is a CSV file with a header row and three columns: `id` (integer),
`city` (string), and `temp` (integer).

1. Load the CSV with **pandas**.
2. Write the whole DataFrame to `/app/data.parquet` as an **Apache Parquet** file using
   the **pyarrow engine**.
3. Compute the **sum** of the `temp` column and write that integer (no trailing
   newline, no spaces) to `/app/answer.txt`.

When you are done:
- `/app/data.parquet` must be a valid Parquet file readable by the `pyarrow.parquet`
  module, containing exactly the three columns `id`, `city`, `temp` (in that order)
  and the same rows as the CSV.
- `/app/answer.txt` must contain only the integer sum of `temp`.</think>