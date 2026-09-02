#!/usr/bin/env bash
# Oracle solution for item-062-hard. Creates the 7 required indexes, measures
# before/after, verifies plans and rows, writes /app/report.json.
set -euo pipefail
cd /app

python3 - <<'PY'
import json, sqlite3, time

SQL = {
    "q1": "SELECT w.lemma FROM senses s JOIN words w ON w.id = s.word_id WHERE s.synset_id = 829",
    "q2": "SELECT synset_id, senserank FROM senses WHERE synset_id = 829 AND senserank = 3",
    "q3": "SELECT COUNT(*) FROM relations WHERE reltype = 'hypernym' AND target_synset = 12345",
    "q4": "SELECT synset_id FROM senses WHERE senserank = 3",
    "q5": "SELECT synset_id FROM senses WHERE senserank + 0 = 3",
    "q6": "SELECT COUNT(DISTINCT synset_id) FROM relations WHERE target_synset = 12345",
    "q7": "SELECT id FROM words WHERE lemma = 'lemma7001'",
}
IDX = {
    "q1": ("idx_senses_synset",          "CREATE INDEX idx_senses_synset ON senses(synset_id)"),
    "q2": ("idx_senses_synset_rank",     "CREATE INDEX idx_senses_synset_rank ON senses(synset_id, senserank)"),
    "q3": ("idx_relations_type_target",  "CREATE INDEX idx_relations_type_target ON relations(reltype, target_synset)"),
    "q4": ("idx_senses_senser",          "CREATE INDEX idx_senses_senser ON senses(senserank)"),
    "q5": ("idx_senses_senser_expr",     "CREATE INDEX idx_senses_senser_expr ON senses(senserank + 0)"),
    "q6": ("idx_relations_target",       "CREATE INDEX idx_relations_target ON relations(target_synset)"),
    "q7": ("idx_words_lemma",            "CREATE INDEX idx_words_lemma ON words(lemma)"),
}
N_RUNS = 20

def explain(cur, sql):
    return [str(r[3]).strip() for r in cur.execute("EXPLAIN QUERY PLAN " + sql).fetchall()]

def timeit(cur, sql, runs=N_RUNS):
    t0 = time.perf_counter_ns()
    for _ in range(runs):
        cur.execute(sql).fetchall()
    return time.perf_counter_ns() - t0

con = sqlite3.connect("file:/app/wn.db", uri=True)
cur = con.cursor()

# Measure every query against the pristine, index-free database FIRST so each
# "before" timing is a real table scan / unindexed lookup.
before = {}
for qid, sql in SQL.items():
    before[qid] = {
        "rows": [tuple(str(c) for c in r) for r in cur.execute(sql).fetchall()],
        "plan": explain(cur, sql),
        "ns": timeit(cur, sql),
    }

# Create all indexes.
for qid in SQL:
    cur.execute(IDX[qid][1])
con.commit()

# Re-measure each query with the full index set in place.
after = {}
for qid, sql in SQL.items():
    after[qid] = {
        "rows": [tuple(str(c) for c in r) for r in cur.execute(sql).fetchall()],
        "plan": explain(cur, sql),
        "ns": timeit(cur, sql),
    }

out = {"queries": []}
for qid, sql in SQL.items():
    b, a = before[qid], after[qid]
    out["queries"].append({
        "id": qid,
        "index": IDX[qid][0],
        "before_plan": b["plan"],
        "after_plan": a["plan"],
        "before_rows": len(b["rows"]),
        "after_rows": len(a["rows"]),
        "rows_unchanged": len(b["rows"]) == len(a["rows"]),
        "before_ns": b["ns"],
        "after_ns": a["ns"],
        "speedup": round(b["ns"] / max(a["ns"], 1), 1),
        "result": sorted(a["rows"]),
    })

con.close()
with open("/app/report.json", "w") as f:
    json.dump(out, f, indent=2)
print("wrote /app/report.json")
PY

exit 0
