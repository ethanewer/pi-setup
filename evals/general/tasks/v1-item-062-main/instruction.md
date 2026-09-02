# Item-062: speed up Wordnet lookups with indexes

You are working inside a container that contains a SQLite database at
`/app/wn.db` following the **Open English Wordnet** relational schema:

| table | columns |
|---|---|
| `synsets` | `id` (PK), `pos`, `definition` |
| `words` | `id` (PK), `lemma` |
| `senses` | `id` (PK), `synset_id`, `word_id`, `senserank` |
| `relations` | `id` (PK), `synset_id`, `target_synset`, `reltype` |

The database is fully populated (15,000 synsets, 30,000 words, ~50k senses,
~70k relations). **No indexes exist yet.**

## Task

Four lookup queries run slowly because SQLite has to scan whole tables. Your job:

1. For each query below, record its plan with
   `EXPLAIN QUERY PLAN <query>` (this is the "before" plan).
2. Run each query and record its result rows and row count (the "before" result).
3. Create indexes so every query stops scanning and uses an index
   (`EXPLAIN QUERY PLAN` shows `SEARCH ... USING INDEX`).
   Use exactly these index names:
   - `idx_senses_synset` ON `senses(synset_id)`
   - `idx_senses_word` ON `senses(word_id)`
   - `idx_relations_target` ON `relations(target_synset)`
   - `idx_senses_senser` ON `senses(senserank)`
4. Re-run each query; the results must be **identical** to the before-results
   (same rows, same order is not required — same row set).
5. Write a report to `/app/report.json` (exact format below).

The four queries (these exact strings are also used by the verifier):

- q1: `SELECT w.lemma FROM senses s JOIN words w ON w.id = s.word_id WHERE s.synset_id = 829`
- q2: `SELECT synset_id FROM senses WHERE word_id = 7001`
- q3: `SELECT COUNT(*) FROM relations WHERE target_synset = 12345`
- q4: `SELECT senserank, COUNT(*) FROM senses WHERE senserank = 3 GROUP BY senserank`

## `/app/report.json` format

```json
{
  "queries": [
    {
      "id": "q1",
      "index": "idx_senses_synset",
      "before_plan": ["SCAN senses", "SCAN words", "SEARCH words USING INDEX sqlite_autoindex_words_1 ..."],
      "after_plan": ["SEARCH senses USING INDEX idx_senses_synset (synset_id=?)", "SEARCH words USING INDEX sqlite_autoindex_words_1 (id=?)"],
      "before_rows": 5,
      "after_rows": 5,
      "rows_unchanged": true,
      "result": [["lemma17", "lemma83"]]
    }
  ]
}
```

Rules for the report:

- `before_plan` / `after_plan`: arrays of the plan lines returned by
  `EXPLAIN QUERY PLAN` (each line trimmed).
- `before_rows` / `after_rows`: row counts of the query before / after adding
  the indexes.
- `rows_unchanged`: `true` iff `before_rows == after_rows`.
- `result`: the **after** query result as a JSON array of arrays; every scalar
  stringified (e.g. `[["lemma17"]]` or `[["3","512"]]`).
- One entry per query, ids `q1`..`q4`.

Leave the four indexes in place in the database when you are done.

## Environment notes

- `sqlite3` CLI and `python3` (with the `sqlite3` module) are available.
- Do not modify the database contents (no INSERT/UPDATE/DELETE/ALTER); only
  create the indexes.
- The verifier re-runs the queries itself against the final database and
  compares against your report; your `result` must match the real data.
