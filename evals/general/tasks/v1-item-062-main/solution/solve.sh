#!/usr/bin/env bash
# Oracle solution for item-062-main: create the 4 indexes, capture plans/results,
# write /app/report.json.
set -euo pipefail
cd /app

python3 - <<'PY'
import json, sqlite3, subprocess, os

SQL = {
    "q1": "SELECT w.lemma FROM senses s JOIN words w ON w.id = s.word_id WHERE s.synset_id = 829",
    "q2": "SELECT synset_id FROM senses WHERE word_id = 7001",
    "q3": "SELECT COUNT(*) FROM relations WHERE target_synset = 12345",
    "q4": "SELECT senserank, COUNT(*) FROM senses WHERE senserank = 3 GROUP BY senserank",
}
IDX = {
    "q1": ("idx_senses_synset", "CREATE INDEX idx_senses_synset ON senses(synset_id)"),
    "q2": ("idx_senses_word", "CREATE INDEX idx_senses_word ON senses(word_id)"),
    "q3": ("idx_relations_target", "CREATE INDEX idx_relations_target ON relations(target_synset)"),
    "q4": ("idx_senses_senser", "CREATE INDEX idx_senses_senser ON senses(senserank)"),
}

out = {"queries": []}
for qid in ("q1", "q2", "q3", "q4"):
    sql = SQL[qid]

    def rows(conn):
        return [tuple(str(c) for c in r) for r in conn.execute(sql).fetchall()]

    def explain(conn):
        return [str(r[3]).strip() for r in conn.execute("EXPLAIN QUERY PLAN " + sql).fetchall()]

    con = sqlite3.connect("file:/app/wn.db", uri=True)
    before = rows(con)
    before_plan = explain(con)

    idxname, ddl = IDX[qid]
    con.execute(ddl)
    con.commit()

    after = rows(con)
    after_plan = explain(con)
    con.close()

    # keep index-only entries: drop every line that does not mention the new
    # index here would hurt before_plan; we record full plans as requested.
    out["queries"].append({
        "id": qid,
        "index": idxname,
        "before_plan": before_plan,
        "after_plan": after_plan,
        "before_rows": len(before),
        "after_rows": len(after),
        "rows_unchanged": len(before) == len(after),
        "result": sorted(after),
    })

with open("/app/report.json", "w") as f:
    json.dump(out, f, indent=2)
print("wrote /app/report.json")
PY

exit 0