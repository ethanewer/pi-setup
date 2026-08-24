`/app/people.csv` is a comma-separated file with a header row and three data columns: `id,name,dept`. Note that **name fields may contain a comma** and are therefore quoted where needed. Example:
```
id,name,dept
1,"Smith, Jane",sales
2,"Brown, Alice",engineering
```
Your task is to read the CSV properly (use `csv` module parsing, honoring quotes) and write a **new CSV** `/app/report.csv` with header `id,name,dept,dept_code` where:

- the `id`, `name`, `dept` columns are carried over from the source,
- `dept_code` is computed as: `sales` -> `01`, `engineering` -> `02`, `support` -> `03`, anything else -> `00`.

Write a program `/app/process_csv.py` that does this, then run it so `/app/report.csv` is produced. The verifier parses `/app/report.csv` with the standard `csv` module and checks that every row's fields match the expected computed values (including rows whose `name` contains a comma).