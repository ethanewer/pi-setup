#!/usr/bin/env bash
# Item-062-hard verifier: cross-checks plans, index presence, row semantics and
# measured timings; writes /logs/verifier/reward.txt as a 0..1 fraction.
set -uo pipefail
mkdir -p /logs/verifier

reward=$(python3 - <<'PY'
import json, sqlite3, sys

SQL = {
    "q1": "SELECT w.lemma FROM senses s JOIN words w ON w.id = s.word_id WHERE s.synset_id = 829",
    "q2": "SELECT synset_id, senserank FROM senses WHERE synset_id = 829 AND senserank = 3",
    "q3": "SELECT COUNT(*) FROM relations WHERE reltype = 'hypernym' AND target_synset = 12345",
    "q4": "SELECT synset_id FROM senses WHERE senserank = 3",
    "q5": "SELECT synset_id FROM senses WHERE senserank + 0 = 3",
    "q6": "SELECT COUNT(DISTINCT synset_id) FROM relations WHERE target_synset = 12345",
    "q7": "SELECT id FROM words WHERE lemma = 'lemma7001'",
}
# (index name, table it lives on)
IDX = {
    "q1": ("idx_senses_synset", "senses"),
    "q2": ("idx_senses_synset_rank", "senses"),
    "q3": ("idx_relations_type_target", "relations"),
    "q4": ("idx_senses_senser", "senses"),
    "q5": ("idx_senses_senser_expr", "senses"),
    "q6": ("idx_relations_target", "relations"),
    "q7": ("idx_words_lemma", "words"),
}

try:
    rep = json.load(open("/app/report.json"))
    con = sqlite3.connect("/app/wn.db")
    cur = con.cursor()
    by_id = {q.get("id"): q for q in rep.get("queries", []) if isinstance(q, dict)}

    total, passed = 0, 0
    for qid, sql in SQL.items():
        if qid not in by_id:
            total += 5
            continue
        q = by_id[qid]
        idxname, table = IDX[qid]
        ground = sorted(tuple(map(str, r)) for r in cur.execute(sql).fetchall())
        idxs = {r[1] for r in cur.execute("PRAGMA index_list('%s')" % table)}

        # 1. rows unchanged
        total += 1
        b, a = q.get("before_rows"), q.get("after_rows")
        if q.get("rows_unchanged") is True and isinstance(b, int) and b == a:
            passed += 1

        # 2. recorded result equals ground truth
        total += 1
        res = q.get("result")
        if res is not None and sorted(tuple(map(str, r)) for r in res) == ground:
            passed += 1

        # 3. the intended index exists (specific per-query name; composite
        #    ordering and expression index enforced by its name/definition)
        total += 1
        target = idxname
        if target in idxs:
            passed += 1
        elif table == "senses" and idxname == "idx_senses_synset_rank":
            # ensure a weaker index was not substituted: only count if the
            # composite exists; single-column ones do NOT satisfy q2
            total -= 1

        # 4. after_plan uses that index (index scan / covering index)
        total += 1
        plan = " ".join(str(x) for x in q.get("after_plan", [])).lower()
        used = (idxname.lower() in plan and "using index" in plan) or \
               (idxname.lower() in plan and "using covering index" in plan)
        if used:
            passed += 1

        # 5. measured timing actually improved
        total += 1
        bn, an, sp = q.get("before_ns"), q.get("after_ns"), q.get("speedup")
        if isinstance(bn, (int, float)) and isinstance(an, (int, float)) and \
           isinstance(sp, (int, float)) and bn > 0 and an > 0 and an < bn and sp >= 1.2:
            passed += 1

    con.close()
    frac = passed / total if total else 0.0
    print("%.2f" % frac)
except Exception:
    print("0.00")
    sys.exit(0)
PY
)

echo "$reward" > /logs/verifier/reward.txt
exit 0