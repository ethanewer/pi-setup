# Gale Spectral Tooling Harness

You are setting up a small analysis toolkit ("gale") for studying the frequency content of
wind-gust recordings. Your working directory is `/app`. You must produce **five
deliverables**. A verifier will later execute every one of them against its own hidden
inputs, in **fresh processes** — nothing may depend on your current session state.

Each deliverable must be a real file at its exact path.

---

## 1. `/app/workbook.ipynb` — Jupyter skeleton workbook

A valid Jupyter notebook file in JSON `nbformat` 4 or greater (a `"cells"` array, top-level
`"nbformat": 4`). It must contain **at least one markdown cell** and **at least one code
cell**:

- **Markdown cell**: the concatenated markdown text (case-insensitive) must contain the word
  `spectral`.
- **Code cell**: at least one code cell must `import matplotlib` and call a plotting function
  on the `matplotlib.pyplot` interface, i.e. one of `plt.plot(`, `plt.bar(`, `plt.scatter(`,
  `plt.step(` or `plt.hist(`. Run the `Agg` backend so it works on a headless server without a
  display. The code cell must run without raising an error (it may save a plot to a temp file).
  `matplotlib`, `nbformat`, `nbclient` and `ipykernel` are already installed.

The verifier unpacks the notebook, checks the cell types, checks the markdown topic term, and
executes the plotting code cell.

---

## 2. `/app/plugin.vim` — Vim window-layout plugin

A Vimscript plugin. When `source`d it must define the command:

```
:GaleReport <outfile>
```

`:GaleReport <path>` writes a plain-text report of the **current active window layout** to
that path (overwriting it). Format, one summary line then one line per window:

```
windows=N
window=1:rows=R1:cols=C1
window=2:rows=R2:cols=C2
...
```

- `N` = current count of windows (`winnr('$')`).
- For each window `i` (1-based), `Ri`/`Ci` = its height/width (`winheight(i)`/`winwidth(i)`),
  both strictly positive integers.
- The report must reflect the live session from which `:GaleReport` is invoked.

Guidance:
- Guard against double-loading with `if exists('g:...')  finish  endif`.
- Use `winnr('$')`, `winheight()`, `winwidth()`; no hard-coded values.

The verifier launches a brand-new headless Vim (`vim -n -es -N -u NONE -i NONE`) each time,
sources `/app/plugin.vim`, creates several windows via `:split`/`:vsplit`/`:new`, runs
`:GaleReport`, and checks the report matches the actual geometry for multiple distinct
layouts (1, 2 and 3 windows). Must work from a clean fresh session.

---

## 3. `/app/topk.awk` — ranked top-k in gawk

A gawk program invoked as:

```
gawk -f /app/topk.awk -v k=K input.csv
```

**Input**: CSV with header `frame,bin,magnitude` — one row per (frame, spectral bin). Frame
ids and bin ids are zero-based integers; magnitudes are **non-negative integers**. A bin id
appears at most once per frame.

**Input handling** (your program must stay correct on messy input):
- Skip the header line.
- Skip any blank line.
- Skip any row with **fewer than 3 CSV fields** (malformed/short rows).
- Skip any second header line (any row whose first field is the literal `frame`).

**Output** to stdout: a header line exactly `frame,bin,magnitude,rank`, then one line per
emitted peak, `frame,bin,magnitude,rank`:

- Frames in **ascending numerical frame order**.
- Within a frame, the top-`K` bins sorted by **descending magnitude**; on equal magnitude,
  **ascending bin id** (smaller bin first).
- rank is `1..K` in that order.
- A frame with fewer than `K` bins emits only the bins it has (no rank filler).
- `K` comes from `-v k=` and is a positive integer.
- Magnitudes print as integers.

Example with `k=2` for input
```
frame,bin,magnitude
0,0,12
0,1,48
0,2,33
```
output is
```
frame,bin,magnitude,rank
0,1,48,1
0,2,33,2
```

The verifier runs `/app/topk.awk` on hidden magnitude CSVs with different `k` values — ties,
more bins than `k`, fewer bins than `k`, `k=1`, a header-only dirty file, and blank/malformed
rows — and compares exact text to a reference ranking.

---

## 4. `/app/filter.jq` — jq record-transform pipeline

A jq filter program. Run as `jq -f /app/filter.jq input.json` where the input file is a JSON
**array of record objects**. Implement the transform pipeline and emit a new array of objects:

1. **Filter**: keep only records with `status == "ok"` (drop `warn`, `fail`, `pending`, …).
2. **Rename** `colour` → `hue`.
3. **Format date**: `timestamp` is an ISO string such as `2024-05-06T12:34:56Z`; emit a `day`
   field equal to the date part `YYYY-MM-DD` (the text before the `T`).
4. **Length**: `tagcount` = number of elements in `tags`.
5. **First element**: `firsttag` = `tags[0]`, or `null` when `tags` is empty.
6. Drop the original `colour`, `timestamp`, `tags`, `status` fields from each output object.

Each output object has exactly the keys `id`, `hue`, `day`, `tagcount`, `firsttag`; the final
array is `sort_by(.day, .id)` where `id` is a string.

Input record example:
```json
{"id":"a-7","status":"ok","colour":"teal","timestamp":"2024-03-05T11:22:33Z","tags":["x","y"]}
```
becomes one output object:
```json
{"id":"a-7","hue":"teal","day":"2024-03-05","tagcount":2,"firsttag":"x"}
```

The verifier runs `/app/filter.jq` on hidden arrays — mixed statuses, empty `tags`, arrays
whose records are all dropped (expect `[]`), and day/id ordering — and compares to a
reference. It compares with `jq -S`, so field order inside an object does not matter, but the
full set of fields/values must match.

---

## 5. `/app/pipeline.sh` — orchestrator shell pipeline

An **executable** bash script with two modes:

- `pipeline.sh full OUTDIR` — full pipeline: a `python3` stage synthesizes a deterministic
  signal and computes STFT magnitude frames, writing `OUTDIR/magnitudes.csv` (header
  `frame,bin,magnitude`, integer magnitudes); then the script produces `OUTDIR/peaks.csv`
  (same ranked-peak format as part 3) out of that same magnitudes file.
- `pipeline.sh subset MAGCSV OUTCSV` — **subset mode**: reads ONLY the magnitude CSV
  `MAGCSV` and writes `OUTCSV` (ranked-peak format). In this mode it must run the ranker
  with **only `awk`** and must **never invoke `python`**. It must resolve the `awk` binary
  through `PATH` — invoke it as a bare `awk` (as in `awk -f /app/topk.awk …`), never via an
  absolute path like `/usr/bin/awk`.

The peak default `k` is `3`, overridable via the environment variable `TOPK_K` (a positive
integer), which must be honored in both `full` and `subset`. Do `chmod +x /app/pipeline.sh`.

The verifier:
- Runs `pipeline.sh full` and checks both output files exist and that `peaks.csv` matches
  the reference ranking of the generated `magnitudes.csv`.
- Runs `pipeline.sh subset` on a hidden magnitude CSV while putting a **fake `python3`** and a
  **recording `awk` shim** first on `PATH`: it must produce the correct peaks WITHOUT the
  fake `python3` ever running, and must invoke the `awk` from `PATH` (the shim is called).
  If the script calls `python3` in subset mode, or uses `/usr/bin/awk` directly, the check
  fails.

---

## Final requirements

- Work only inside `/app`; end with all five files present. Nothing reads `/tests` or
  `/solution`.
- Deterministic integer math throughout.
- Everything must work from a clean fresh process. Do not rely on state left by other steps.