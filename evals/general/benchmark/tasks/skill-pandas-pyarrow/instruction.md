# pandas with the PyArrow backend

`/app/data.csv` is a CSV file with a header row and two columns: `region` (a string)
and `amount` (an integer).

Use **pandas** to load this file with the **PyArrow-backed dtype backend enabled**,
i.e. call `pandas.read_csv("/app/data.csv", dtype_backend="pyarrow")`. Do not
convert to NumPy-backed dtypes afterwards.

1. Write the loaded DataFrame to `/app/out.parquet` using the **pyarrow** engine
   (`df.to_parquet("/app/out.parquet", engine="pyarrow")`).
2. Then compute the **sum of `amount` per `region`** from that DataFrame and write
   the result to `/app/sums.txt`, one line per region in **descending total order**
   (largest sum first), formatted as `region sum` separated by a single space.
   The `sum` is an integer.

The output files must be real Parquet/pandas artifacts:
- `/app/out.parquet` must be readable by `pyarrow.parquet` and, when read back into
  pandas, must expose **PyArrow-backed dtypes** for both columns (`string[pyarrow]`
  for `region` and `int64[pyarrow]` for `amount`).
- `/app/sums.txt` must exactly match the grouped sum.
