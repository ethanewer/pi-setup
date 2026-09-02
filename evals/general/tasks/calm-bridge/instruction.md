# Calm Bridge — recovering a partially lost, byte-transformed SQLite ledger

You are a database forensics engineer. A small CRM database (`/app/trade/ledger.db`)
was damaged during a crash and **byte-transformed**. Your job is to author a single
reusable Python program `/app/recover.py` that detects the transform on the journal,
reverses it, recovers the intact rows, runs an in-database cleaning pipeline, and
exports the surviving records. The same program is then run by an independent
verifier against damaged input files you never see, so it must be *generic*: it
drives purely from the files it is given.

## Deliverables (all under `/app`)

| Path | What it must contain |
|---|---|
| `/app/recover.py` | the reusable program described below (CLI subcommands) |
| `/app/merged.json` | the recovered+cleaned result for the visible fixture in `/app/trade` |
| `/app/trial_*.csv` (i.e. `/app/trial_0001.csv` … `/app/trial_0003.csv`) | numbered CSVs, one per recovery trial |
| `/app/fd.txt` | content recovered from an unlinked-but-open file descriptor |

`recover.py` must be executable and offer at least these subcommands (the verifier
calls exactly these):

```
python3 /app/recover.py run  <db> <journal> <out.json>
python3 /app/recover.py csv  <db> <journal>
python3 /app/recover.py fd   <seed_file> <out>
python3 /app/recover.py perf <scaled_db>
```

- `run` performs full recovery + cleaning and writes `<out.json>`.
- `csv` performs the same recovery + cleaning and prints CSV rows to stdout (rows
  only, a header line included); it is used to create the trial tables.
- `fd` recovers the content of an unlinked-but-open file descriptor (see below).
- `perf` warms up, then times one indexed query on a large metrics table and prints
  the **elapsed milliseconds as a bare integer** to stdout.

Everything is pure Python stdlib (`sqlite3`, `os`, `json`, `csv`, `sys`, `time`,
`tempfile`). `/app/files/tool/gen.py` is provided: it builds sample scenarios
(`gen.py fresh <outdir> <seed> <nrows>`, `gen.py seed <path>`, `gen.py scaled <path>
<nrows>`) — read it as the authoritative statement of the input format. You may use
it during development to generate as many local cases as you like, but
`recover.py` must **not** import or call it at answer time.

## Scenario — what actually happened

The database `ledger.db` holds table

```
contacts(id INTEGER PRIMARY KEY, name TEXT, msisdn TEXT, email TEXT, phone TEXT, region TEXT)
```

At crash time the truth table `id=1..N` had **all** rows, but they were partitioned
across two on-disk artifacts, so neither contains everything:

1. `ledger.db` — a valid SQLite file containing the *checkpointed* subset of rows.
   (Some ids are simply absent from it — those rows are not in this file.)
2. `ledger.wal` — the *journal* holding the remaining (un-checkpointed) committed
   rows. Some journal entries may also duplicate an id that is already in the DB
   (un-checkpointed re-writes) with *different* values. The journal is **byte-wise
   transformed**: every byte of the native file is XORed with one single key byte,
   so its header bytes no longer look native.

A separate damage model applies: a fraction of ids was **lost forever** (their pages
were not salvageable) — they are in neither the DB nor the journal and must simply
not appear in your output. Nothing marks them; you recover *whatever surviving rows
you can read*.

### The native journal format (after you reverse the transform)

- Line 1 is exactly the magic `WJNT1`.
- Each following line is one record: `id<TAB>name<TAB>msisdn<TAB>email<TAB>phone<TAB>region`.
- Rows are in file order.

### Detecting the transform (do this, do not skip it)

Read the journal's leading bytes. If the first line equals `WJNT1` the journal is
already native (key `0`) and you can parse it directly. Otherwise the bytes are
`native[i] XOR key` for a single `key` in `1..255` — brute-force all 256 candidates
(the one whose reversed bytes start with the native magic is the key) and reverse it
before parsing. Structures with the *wrong* header must never be treated as native.

## Cleaning pipeline (exact contract — the verifier enforces equality)

Operate on the **merged** recoverable rows (DB rows in id order, then journal rows in
file order), as SQL statements if you can (see "SQL evidence" below). Do all of these:

1. `name`  → lower-case (and trim surrounding whitespace).
2. `msisdn` → strip every non-digit character; the digit-only string cast to an
   integer goes into a **new** integer field `msisdn_d`. When the digit-only string
   is empty, `msisdn_d` is `null`.
3. Delete any row whose `email` **and** `phone` are both empty/missing.
4. De-duplicate by `id`, keeping the **first** occurrence in merged order (so a DB
   row wins over a same-id journal duplicate).
5. Sort ascending by `id`.

Your JSON output is an array of objects with exactly the keys
`id, name, msisdn, msisdn_d, email, phone, region`, where `msisdn_d` is an integer
or `null`, `email`/`phone` are strings or `null` when absent, and the array is
sorted by `id` with **no duplicate ids**.

The CSV output (for `csv` / trials) has header
`id,name,msisdn,msisdn_d,email,phone,region` and the same rows, with `msisdn_d`
blank when null.

### SQL evidence

`clean()` must be a genuine in-database cleaning: build the merged rows into a fresh
SQLite table and express the lower-casing, digit-extraction/CAST, deletion and
de-duplication as real SQL statements (a small `digits()` helper registered with
`conn.create_function` is fine — the statements that use it are still SQL). The
verifier checks the *resulting rows*; doing the cleaning in Python instead of SQL
fails the intent.

## Open-file-descriptor recovery (`fd`)

A background process still holds a file descriptor to an inode that has been
unlinked. `recover.py fd <seed_file> <out>` must: read `<seed_file>`'s bytes into
memory, write them to a fresh temp file whose descriptor stays open, **unlink** the
temp path from the namespace, then recover the bytes by reading back through the
still-open descriptor and write them to `<out>`. `<out>` must byte-equal
`<seed_file>`.

## Performance gate (`perf`)

A hidden scaled database contains table
`metrics(id INTEGER PRIMARY KEY, grp INTEGER, val REAL, stub TEXT)` with well over a
million rows and **no pre-built index** (the generator deliberately leaves the table
bare). `perf <db>` must make the query `SELECT COUNT(*) FROM metrics WHERE grp = 7`
fast after warm-up: create any index it needs, run the query several times to warm
caches/plans, then time one execution and print the integer milliseconds. The
verifier requires the printed value to be below a few seconds on the hidden scaled
database.

## Visible fixture to develop against

`/app/trade/ledger.db` and `/app/trade/ledger.wal` are present (a fixed seed). A good
round-trip during development:

1. recover with your `run`, write JSON;
2. verify ids are unique + sorted, and the cleaning looks right;
3. regenerate **new** local cases yourself with
   `python3 /app/files/tool/gen.py fresh <dir> <seed> <nrows>` and repeat — you will
   not know the answer in advance, so use the generator to build many shapes.

`/app/merged.json` (visible), the three `/app/trial_000N.csv` (one per rerun on a
fresh trial fixture), and `/app/fd.txt` must be produced by actually running
`/app/recover.py` on the visible/trial fixtures — do not hand-write them.

## Edge cases the hidden verifier probes (handle all of them)

- Journal transformed with a **nonzero key** → you must infer it and reverse it.
- Journal already native (key `0`) → detect it and parse directly.
- **Malformed journal lines** (wrong number of tab-separated fields, non-numeric
  id) → skip them, keep every well-formed record; never crash the whole run.
- **Empty journal** (all surviving rows live in the DB) → your run must still
  succeed from the DB alone.
- `msisdn` with **no digits** → `msisdn_d` is `null` (string `""`).
- Rows **missing both** `email` and `phone` → dropped by cleaning.
- Rows with only **one** contact → kept.
- **Duplicate ids** across DB and journal → de-duplicated (first occurrence wins).
- Varying damage density: any number of rows may be unrecoverable and simply absent
  from your output.
- `run`/`csv` invoked on fixtures the verifier generated freshly; a wrong header
  parse, missed journal rows, or a cleaning rule that disagrees with this document
  fails the exact-equality check.

## Rules

- Do **not** read `/tests` or `/solution`. Do not make network calls.
- Do not delete or rename `/app/files` or the visible fixture files while developing
  (you may read them).
- Your `recover.py` must do the work from the raw bytes of the files it is given —
  no hard-coded answers, no dependence on `gen.py` at answer time, no reading of
  any expected-output file.

When finished, leave `/app/recover.py`, `/app/merged.json`, `/app/trial_0001.csv`,
`/app/trial_0002.csv`, `/app/trial_0003.csv`, and `/app/fd.txt` in place.
