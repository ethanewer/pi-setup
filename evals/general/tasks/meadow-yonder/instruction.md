# Meadow Yonder — data-log reporting

You are the on-call platform engineer for **Halcyon Hosting**. The night-shift
automation is broken and you must ship four small, reusable pieces of tooling
plus the exact reports they compute. Everything is under `/app`. Do **not**
modify the provided inputs under `/app/data` (they are read-only references). Do
**not** read `/tests` (hidden and irrelevant to you).

Provided inputs (already on disk):

| Path | Content |
|------|---------|
| `/app/data/access.log` | line-oriented web-server access log |
| `/app/data/records.csv` | a CSV full of records |
| `/app/data/process_csv.py` | a CSV normalizer with a bug (see §2) |
| `/app/data/cluster_probe` | probe that refreshes a cluster-state file |
| `/app/data/cluster_state` | current cluster state (`total=`/`idle=`) |
| `/app/data/probe_count` | counter read & advanced by `cluster_probe` |

Python 3 is available as `python3`. Bash, `seq`, `date`, `sed` are available.

---

## 1. Access-log parser `/app/logstats.py`

Write an executable Python script `/app/logstats.py` whose CLI is:

```
python3 /app/logstats.py <LOG_FILE>
```

It reads a line-oriented web-server access log and writes exactly two lines to
stdout:

```
total=<N>
unique=<M>
```

where `N` is the **total request count** and `M` is the **distinct
client-address count**.

**Classification rules (must match exactly — hidden logs probe them):**

- Strip each line of surrounding whitespace.
- **Skip** the line if it is empty/whitespace-only, or if it starts with `#`
  (comment). These are never requests and never count toward `N` or `M`.
- Otherwise the **first whitespace-delimited token** of the line is the client
  address. A client address is valid only if it is **non-empty AND contains at
  least one digit AND is made only of** `[A-Za-z0-9._:-]` (letters, digits,
  dot, underscore, colon, hyphen). A token such as `-`, `"`, `[broken]`, or a
  bare word with no digit is **not** a valid client.
- If the first token is a valid client address, the line is a **request**:
  increment `N` by one and add the token to the distinct set.
- If the first token is not a valid client address, the line is malformed and
  is **skipped** (counts as nothing).
- `M` is the size of that set. Duplicate addresses count **once**.

This is the deliverable you run to produce the report in §5.

---

## 2. Fix the CSV normalizer `/app/fixed_script.py`

`/app/data/process_csv.py` is *supposed* to write **exactly one output line per
record**, but it has a **newline-accumulation bug**: it never strips the trailing
newline off each source line, so the source newline survives into the last field
and then a second newline is appended — every record spills onto an extra blank
line (the output has roughly twice as many lines as records).

You must **fix the missing string-strip** and ship the corrected program as
`/app/fixed_script.py` (executable), with the same CLI:

```
python3 /app/fixed_script.py <input.csv> <output.csv>
```

The fixed program's contract:

- A **record line** is any input line that, after stripping surrounding
  whitespace, is non-empty and does **not** start with `#` (a comment). Blank
  lines and `#` comment lines produce **no** output line.
- Each record produces **exactly one** output line.
- Each line's comma-separated **fields are trimmed of surrounding whitespace**
  (this includes a `\r` from `\r\n` endings and any trailing spaces) and
  re-joined with a single comma.
- The output file must contain **zero blank lines** and exactly the one-line-per
  record produced above. A record whose fields are `a, 1 ,b` must come out as
  `a,1,b`.

It must tolerate `\r\n` line endings, trailing spaces on a line, an input with
**no trailing newline** on the last line, and even an **empty** input (produce
an empty output, no error).

You run this on the shipped data to satisfy §3's dependency.

---

## 3. Cluster-state sampler `/app/sample_cluster.sh`

Write an executable bash script `/app/sample_cluster.sh` that samples a running
cluster on a fixed interval and **appends** well-formed CSV rows to a log file.

CLI:

```
bash /app/sample_cluster.sh <samples> <interval_sec> <logfile> [probe] [state_file]
```

- `probe` — path to a state-refresh script (default `/app/data/cluster_probe`);
- `state_file` — where the probe writes `total=`/`idle=` (default
  `/app/data/cluster_state`).

Behavior — repeat exactly `samples` times:

1. Run the probe (`.bash "$probe" "$state_file"`), which refreshes the state
   file. (If the probe file does not exist, simply leave the state file as is.)
2. Read `total` and `idle` from the state file (two `key=value` lines). Treat an
   unreadable/missing value as `0`. Normalize both to non-negative integers.
3. Compute `fraction = idle / total` rounded to **3 decimal places** (printed
   e.g. `0.667`). If `total == 0`, `fraction` is `0.000`.
4. Append one row to `<logfile>`:

   ```
   <timestamp>,<total>,<idle>,<fraction>
   ```

   where `<timestamp>` is the current epoch seconds (`date +%s`).
5. Between samples, `sleep` the `interval_sec` (except after the last sample).

The row format is exactly `timestamp,total,idle,fraction` — no spaces. Use a
script `probe` argument is passed on so different state styles are not hardcoded.

Dispatched run (this also produces `/app/cluster.log`, below):

```
bash /app/sample_cluster.sh 5 1 /app/cluster.log
```

That run should give `/app/cluster.log` exactly **5** well-formed rows.

---

## 4. Exact-format computed answer `/app/compute_answer.py` + `/app/answer.txt`

Write an executable Python script `/app/compute_answer.py`:

```
python3 /app/compute_answer.py <cluster.log> <report.txt> [outfile]
```

It computes:

```
answer = (sum of the `idle` column over all rows of <cluster.log>)
       + (the `unique` count read from <report.txt>)
```

and writes the **result as a single line holding only the non-negative integer
digits** (no delimiter, no padding, no labels; `0` when zero) to stdout, and,
when `outfile` is given, the identical one-line content to that file.

`<report.txt>` contains the `total=`/`unique=` lines produced by
`/app/logstats.py`; parse the `unique=` value. Rows in `<cluster.log>`
are `timestamp,total,idle,fraction`; if a row is malformed skip it. Missing
files read as zeros.

Produce the final deliverable `/app/answer.txt` by running it on your report and
cluster-log (the exact content matters — it is compared character-for-character).

---

## Deliverables (all under `/app`) — every one is verified

| Path | What it must be |
|------|-----------------|
| `/app/logstats.py` | executable parser §1 |
| `/app/report.txt` | output of running `python3 /app/logstats.py /app/data/access.log` — exactly two lines `total=<N>\nunique=<M>\n` |
| `/app/fixed_script.py` | executable fixed CSV normalizer §2 (one line per record) |
| `/app/sample_cluster.sh` | executable bash sampler §3 |
| `/app/cluster.log` | exactly 5 rows from `bash /app/sample_cluster.sh 5 1 /app/cluster.log` |
| `/app/compute_answer.py` | the executable answer computer §4 |
| `/app/answer.txt` | the exact single-line integer answer for the shipped data |

## Success

You are done when: `report.txt` holds the correct `total`/`unique` for the
shipped log; `fixed_script.py` turns any CSV (including the edge cases in §2)
into one clean line per record; `sample_cluster.sh` emits exactly `samples`
well-formed `timestamp,total,idle,fraction` rows on a fixed interval, correct;
answer is a single-line digit integer that equals idle-sum + unique for the
shipped data; and each of the three reusable programs (`logstats.py`,
`fixed_script.py`, `sample_cluster.sh`, `compute_answer.py`) generalizes to new
inputs. Leave the provided `/app/data` inputs untouched.