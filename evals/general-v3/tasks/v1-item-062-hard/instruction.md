# Item-062 (hard): query-planning forensic on a large Wordnet DB

Inside the container there is a **large** SQLite database at `/app/wn.db`
following the Open English Wordnet relational schema:

| table | columns |
|---|---|
| `synsets` | `id` (PK), `pos`, `definition` |
| `words` | `id` (PK), `lemma` |
| `senses` | `id` (PK), `synset_id`, `word_id`, `senserank` |
| `relations` | `id` (PK), `synset_id`, `target_synset`, `reltype` |

Sizes are ~120k synsets, ~200k words, ~400k senses, ~600k relations.
The database contains **no user indexes** (only primary-key indexes).

## Mission

Seven queries below currently force table scans. Speed them up with SQLite
indexes, **without changing any result**, and prove it quantitatively.
Two traps await: one query cannot be helped by a plain column index at all
(you must reason about *expression indexes*), and one query is only satisfied
by the *correct column order* in a composite index.

## The seven queries (exact strings the verifier uses)

- q1  `SELECT w.lemma FROM senses s JOIN words w ON w.id = s.word_id WHERE s.synset_id = 829`
- q2  `SELECT synset_id, senserank FROM senses WHERE synset_id = 829 AND senserank = 3`
- q3  `SELECT COUNT(*) FROM relations WHERE reltype = 'hypernym' AND target_synset = 12345`
- q4  `SELECT synset_id FROM senses WHERE senserank = 3`
- q5  `SELECT synset_id FROM senses WHERE senserank + 0 = 3`
- q6  `SELECT COUNT(DISTINCT synset_id) FROM relations WHERE target_synset = 12345`
- q7  `SELECT id FROM words WHERE lemma = 'lemma7001'`

## Guidance (do not skip)

1. Before touching anything, run `EXPLAIN QUERY PLAN <q>`, run `<q>`, and time it
   (`python3 -c "import time,timeit…"` or the CLI `.timer on`). Record `before_*`.
2. Decide the index(es) per query, keeping in mind:
   - q2: a single-column index on `synset_id` **or** on `senserank` can only
     serve one equality; the plan you must achieve uses one composite index
     with both columns, ordered `(synset_id, senserank)`.  The verifier looks
     for `idx_senses_synset_rank` specifically.
   - q5: `senserank + 0` is an *expression on the column* – a normal
     `ON senses(senserank)` index is invisible to it. You need an
     **expression index**, e.g. `CREATE INDEX idx_senses_senser_expr ON senses(senserank + 0)`.
   - q3 vs q6: both live on `relations`; q3 filters `(reltype, target_synset)`,
     q6 filters `target_synset` alone. A composite leading with `reltype`
     cannot serve q6. You need **two indexes** on `relations` for the plans below.
3. After a query's plan shows `SEARCH ... USING INDEX`, re-run the query: the
   result must be identical (same rows; sort order irrelevant). Confirm the
   timing really dropped; if an "optimisation" does not change the plan from a
   `SCAN`, it is wrong – undo it.
4. Leave all indexes in the database.

## Deliverable: `/app/report.json`

```json
{
  "queries": [
    {
      "id": "q1",
      "index": "idx_senses_synset",
      "before_plan": ["SCAN senses", "…"],
      "after_plan": ["SEARCH senses USING INDEX idx_senses_synset (synset_id=?)", "…"],
      "before_rows": 6,
      "after_rows": 6,
      "rows_unchanged": true,
      "before_ns": 1230000,
      "after_ns": 42000,
      "speedup": 29.3,
      "result": [["lemma17"], ["lemma83"]]
    }
  ]
}
```

Field rules:

- `index`: the index that makes the query fast (q2: `idx_senses_synset_rank`;
  q5: `idx_senses_senser_expr`; q6: `idx_relations_target`; q7: `idx_words_lemma`;
  q1: `idx_senses_synset`; q3: `idx_relations_type_target`; q4: `idx_senses_senser`).
- `before_plan`/`after_plan`: the full `EXPLAIN QUERY PLAN` output (array of lines).
- `before_rows`/`after_rows`: row counts. `rows_unchanged`: `before_rows == after_rows`.
- `before_ns`/`after_ns`: total wall time in **nanoseconds** for the **same**
  number of executions (e.g. 20 runs) of the query before/after the index,
  measured with `time.perf_counter_ns()`.
- `speedup`: `before_ns / after_ns` (float, one decimal).
- `result`: the after-result as JSON arrays of strings, rows sorted.

One entry per query (ids `q1`..`q7`). Only tag the file when all rows are
unchanged, all plans use the intended index, and every `after_ns < before_ns`.

## Environment

`sqlite3` CLI and `python3` (with stdlib `sqlite3`) available. Do not modify
table contents. The verifier re-executes the queries itself against the final
database and cross-checks your report entries.