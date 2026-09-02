# ZephyrGrid batch pipeline

A transmission-planning ops team at **ZephyrGrid** needs a one-stop batch pipeline.
Given a small portfolio in `/app/input/`, you must write a **Python program**
`/app/solve.py` that emits six byte-exact artifacts. The program is run **by an
external checker on other batches it supplies** — not just on your input — so it
must be written generally, obey the exact contract below, and run cleanly.

## Deliverables (the checker executes these)

1. `/app/solve.py` — the pipeline script (you write it).
2. Emitted by running `/app/solve.py /app` on the visible basket:
   - `/app/plans.jsonl`
   - `/app/decision.txt`
   - `/app/result.csv`
   - `/app/answer.json`
   - `/app/output/results.json`
   - `/app/ledger.xlsx`

Run the program yourself so all six reflect its real behaviour.

## CLI contract

`python3 /app/solve.py [WORKDIR]`

- No argument  → `WORKDIR = /app`.
- With one argument → the program reads `<WORKDIR>/input` and writes its six
  artifacts into `<WORKDIR>` (i.e. `<WORKDIR>/plans.jsonl`, ...). The checker
  invokes the 1-argument form on fresh hidden workdirs it constructs and
  compares the written files; it also invokes the 0-argument form and compares
  `/app/...`. Your program MUST therefore be correct on arbitrary new batches,
  not just the one in `/app/input`.

## Input format

`/app/input/projects.csv` — header line:
```
id,batch,cost,benefit,capacity,revenue,life,rate
```
One portfolio row per line. `cost` and `benefit` are non-negative integers;
`capacity`, `revenue`, `rate` are finite decimals; `life` is a positive
integer; `id` and `batch` are strings. A project's **cost** and **benefit** are
units used for selection; `capacity`, `revenue`, `life`, `rate` are its shape.

`/app/input/config.json` — a single JSON object:
```json
{"salt": "<hex digits>", "iterations": <positive integer>, "budget": <integer>}
```
Note the config key is exactly `"salt"` (do not rename it).

## Semantics

1. **Optimise (0/1 knapsack):** pick a subset of projects with total `cost`
   ≤ `budget` that **maximises total `benefit`** (the integer objective). The
   chosen subset is `invest=yes` for every picked project and `invest=no`
   for every other; `defer` is the opposite (`yes` when not invested,
   `no` when invested). If several subsets tie on benefit, break the tie by
   preferring NOT to invest lower-`index` (earlier-row) projects. The basket is
   scale and **never heads a tie** — any correct optimum is unique here.
2. **NPV:** for each project compute
   `npv = sum_{t=1..life} revenue / (1+rate)^t  -  cost`.
   `total_npv` is the sum of `npv` over the **invested** projects only.

## Output formats (byte-exact)

1. `/app/plans.jsonl` — one compact JSON object per line, **in the same order
   as the input rows** (one record per request):
   ```json
   {"id":"...","batch":"...","shape":{"capacity":<float>,"life":<int>,"revenue":<float>}}
   ```
   Key order is exactly `id`, `batch`, `shape`, and `shape` is exactly
   `capacity`, `life`, `revenue`. Compact separators (no spaces). Each line ends
   with a newline.

2. `/app/decision.txt` — one line per project, in input order, plus a final
   total line — exactly:
   ```
   project=<id> invest=yes defer=no
   project=<id> invest=yes defer=no
   npv_total=<total_npv rounded to two decimals>
   ```
   The `npv_total` value is formatted with exactly two decimals (e.g.
   `-678.01`); the file ends with a final newline.

3. `/app/answer.json` — the **optimal integer objective** (maximised total
   benefit) written as a plain integer with **no trailing newline** (e.g.
   `70`).

4. `/app/result.csv` — exact columns, in this exact order, with header row:
   ```
   id,invest,defer,benefit,cost
   ```
   one row per project in input order, `invest`/`defer` are `yes`/`no`,
   `benefit`/`cost` are the integer values. **No extra or missing columns, no
   reordering.** The checker reads it back with `pandas.read_csv(dtype=str)`
   and compares column set/order and string-typed rows.

5. `/app/ledger.xlsx` — an openpyxl workbook whose active sheet is titled
   `ledger`. Row 1 is the header; data rows follow in input order; two summary
   rows come after a blank row. Exact layout:

   - Row 1, cells A1..F1 = `id`, `invest`, `defer`, `benefit`, `cost`, `npv`.
   - For project `i` (1-indexed), its data row is `i+1`: A=`id`, B=`invest`,
     C=`defer`, D=`benefit` (int), E=`cost` (int), F=`npv` rounded to two
     decimals (numeric).
   - Summary block at `sr = <number_of_projects> + 3`:
     `A{sr}` = `total_benefit`, `B{sr}` = max benefit (int);
     next row `A{sr+1}` = `total_npv`, `B{sr+1}` = `total_npv` rounded to two
     decimals (numeric).
   Cells are written via the openpyxl **API** and must appear at exactly these
   addresses.

6. `/app/output/results.json` — a stable, schema-exact JSON object:
   ```json
   {
     "salt": "<salt>",
     "iterations": <iterations>,
     "files": [
       {"path": "<relative path>", "hex": "<64 lowercase hex>"},
       ...
     ]
   }
   ```
   `files` is sorted ascending by `path`. The `path`s are the **relative paths
   from WORKDIR** of exactly these files: `answer.json`, `decision.txt`,
   `input/projects.csv`, `plans.jsonl`, `result.csv`. (The binary `ledger.xlsx`
   is deliberately NOT hashed here.) The `hex` index is deterministic:
   ```
   payload = utf8(salt + "|" + path) + file_bytes
   d = sha256(payload).hexdigest()
   repeat (iterations - 1) more times: d = sha256(utf8(d)).hexdigest()
   ```
   `iterations` may be 1 (giving a single sha256, after the salt+path payload,
   with no repeated hashing). Emit JSON with two-space indent and a trailing
   final newline; keys in the order `salt`, `iterations`, `files`.

## Constraints

- Do NOT modify, rename, delete, or hard-code the input files.
- Use only the standard library plus `openpyxl` (installed). `pandas` is
  installed too but you do not need it.
- The program must never read `/tests`, `/solution`, or any checker data.
- The program must exit cleanly (status 0) on the 0- and 1-argument forms.

## Hints on what hidden cases probe

Hidden baskets reuse the same contract with fresh values, different `salt`,
different `iterations` (including `1`), and different `budget`s: a case with an
investable project of **cost 0** and several projects too expensive to invest,
and a case with a strict budget **equal to the exact total cost** of the chosen
set. All optima are unique, so a correct general solver is either right for
every basket or wrong for every basket. A partial/hard-coded solution will fail
the hidden runs.