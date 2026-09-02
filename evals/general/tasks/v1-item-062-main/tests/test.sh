#!/usr/bin/env bash
# Item-062-main verifier:
# Recomputes expected query results from the final DB and checks the agent's
# report.json preserved rows and recorded the indexes/plans. Reward is the
# fraction of checks passed; all pass => 1.00.
set -uo pipefail
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json, sqlite3, sys

SQL = {
    "q1": "SELECT w.lemma FROM senses s JOIN words w ON w.id = s.word_id WHERE s.synset_id = 829",
    "q2": "SELECT synset_id FROM senses WHERE word_id = 7001",
    "q3": "SELECT COUNT(*) FROM relations WHERE target_synset = 12345",
    "q4": "SELECT senserank, COUNT(*) FROM senses WHERE senserank = 3 GROUP BY senserank",
}
IDX = {
    "q1": ("idx_senses_synset", "senses"),
    "q2": ("idx_senses_word", "senses"),
    "q3": ("idx_relations_target", "relations"),
    "q4": ("idx_senses_senser", "senses"),
}

try:
    rep = json.load(open("/app/report.json"))
except Exception:
    print("0.00")
    sys.exit(0)

try:
    con = sqlite3.connect("/app/wn.db")
    cur = con.cursor()
    by_id = {q.get("id"): q for q in rep.get("queries", []) if isinstance(q, dict)}
    total, passed = 0, 0
    for qid, sql in SQL.items():
        if qid not in by_id:
            total += 4  # missing block: all 4 sub-checks fail
            continue
        q = by_id[qid]
        idxname, table = IDX[qid]
        ground = sorted(tuple(map(str, r)) for r in cur.execute(sql).fetchall())

        # 1. rows unchanged
        total += 1
        b, a = q.get("before_rows"), q.get("after_rows")
        if q.get("rows_unchanged") is True and isinstance(b, int) and b == a:
            passed += 1

        # 2. recorded result equals ground truth (sorted sets)
        total += 1
        res = q.get("result")
        if res is not None and sorted(tuple(map(str, r)) for r in res) == ground:
            passed += 1

        # 3. index exists
        total += 1
        idxs = {r[1] for r in cur.execute("PRAGMA index_list('%s')" % table)}
        if idxname in idxs:
            passed += 1

        # 4. after_plan line mentions the index as an index scan
        total += 1
        plan = " ".join(str(x) for x in q.get("after_plan", [])).lower()
        if idxname.lower() in plan and "using index" in plan or idxname.lower() in plan and "using covering index" in plan:
            passed += 1

    con.close()
    frac = passed / total if total else 0.0
    print("%.2f" % frac)
except Exception as e:
    print("0.00")
    sys.exit(0)
PY
)

echo "$reward" > /logs/verifier/reward.txt
exit 0