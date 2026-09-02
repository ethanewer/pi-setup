#!/bin/bash
mkdir -p /logs/verifier

for f in /app/config.json /app/embed_pipe.py /app/notes.md; do
  if [ ! -f "$f" ] || [ ! -s "$f" ]; then
    echo "0.0" > /logs/verifier/reward.txt
    exit 0
  fi
done

python3 - <<'PYEOF'
import json, os, re, subprocess, sys

def write(r):
    open("/logs/verifier/reward.txt", "w").write(repr(r))

try:
    cfg = json.load(open("/app/config.json"))
    checks = {}

    # --- config sanity ---
    checks["config_keys"] = cfg.get("model_id") == "BAAI/bge-small-zh-v1.5" \
        and isinstance(cfg.get("revision"), str)
    rev = cfg.get("revision", "")
    checks["sha_format"] = bool(re.fullmatch(r"[0-9a-f]{40}", rev))

    # --- revision really exists for this model (best effort) ---
    rev_exists = None  # None = unknown (network), True/False = known
    try:
        r = subprocess.run(
            ["curl", "-fsSL", "-o", "/dev/null", "-w", "%{http_code}",
             f"https://huggingface.co/BAAI/bge-small-zh-v1.5/raw/{rev}/config.json"],
            capture_output=True, text=True, timeout=60)
        rev_exists = r.stdout.strip() == "200"
    except Exception:
        rev_exists = None
    checks["revision_exists"] = (rev_exists is None) or (checks["sha_format"] and rev_exists)

    # --- fresh deterministic input ---
    import numpy as np
    rng = np.random.default_rng(48151623)
    qbase = ["学习", "天气", "运动", "美食"]
    dbase = ["深度学习", "天气预报", "田径运动", "北京小吃", "量子物理", "园艺"]
    def noise(pool):
        vs = rng.random()
        return pool[int(vs % len(pool))]
    queries = [f"{q}是什么" for q in [noise(qbase) for _ in range(4)]]
    docs = [f"{noise(dbase)}的相关知识" for _ in range(8)]
    with open("/tmp/fresh_queries.txt", "w", encoding="utf-8") as f:
        f.write("\n".join(queries) + "\n")
    with open("/tmp/fresh_docs.json", "w", encoding="utf-8") as f:
        json.dump(docs, f, ensure_ascii=False)

    # --- run the agent pipeline ---
    a = subprocess.run(
        ["python3", "/app/embed_pipe.py", "--queries", "/tmp/fresh_queries.txt",
         "--docs", "/tmp/fresh_docs.json", "--out", "/tmp/ag_results.json"],
        capture_output=True, text=True, timeout=1200)
    checks["agent_runs"] = a.returncode == 0
    if not checks["agent_runs"]:
        write(0.0)
        print({"agent_runs": False, "err": a.stderr[-500:]}, file=sys.stderr)
        sys.exit(0)

    try:
        ag = json.load(open("/tmp/ag_results.json"))
    except Exception:
        write(0.0)
        sys.exit(0)

    # --- reference recomputation with the same pinned revision ---
    from sentence_transformers import SentenceTransformer
    import numpy as np
    model = SentenceTransformer("BAAI/bge-small-zh-v1.5",
                                revision=cfg["revision"])
    qe = model.encode(queries, normalize_embeddings=cfg.get("normalize", True),
                      convert_to_numpy=True)
    de = model.encode(docs, normalize_embeddings=cfg.get("normalize", True),
                      convert_to_numpy=True)
    S_ref = (np.asarray(qe, dtype=np.float64)
             @ np.asarray(de, dtype=np.float64).T)

    shape_ok = (np.asarray(ag["similarity"]).shape == S_ref.shape)
    checks["shape"] = shape_ok
    if shape_ok:
        S_ag = np.asarray(ag["similarity"], dtype=np.float64)
        checks["similarity"] = bool(np.max(np.abs(S_ag - S_ref)) < 1e-4)
    else:
        checks["similarity"] = False

    top2_ref = []
    for row in S_ref:
        top2_ref.append(sorted(range(len(docs)), key=lambda j: (-row[j], j))[:2])
    ag_top2 = ag.get("top2")
    exact = ag_top2 == top2_ref
    if not exact and isinstance(ag_top2, list) and len(ag_top2) == len(top2_ref):
        # Tolerate swaps among near-tied scores: accept the agent's picks if,
        # for every query row, both picked docs score within 1e-4 of the
        # reference top-2 cutoff AND the pairwise ordering deviation is due
        # only to such near-ties.
        ok = True
        for qi, (row, picks) in enumerate(zip(S_ref, ag_top2)):
            if not isinstance(picks, (list, tuple)) or len(picks) != 2:
                ok = False
                break
            ref_picks = top2_ref[qi]
            try:
                picks = [int(p) for p in picks]
            except Exception:
                ok = False
                break
            if len(set(picks)) != 2 or any(p < 0 or p >= len(docs) for p in picks):
                ok = False
                break
            sets_match = set(picks) == set(ref_picks)
            # score gap between picked and reference cutoff must be tiny
            ref_cut = row[ref_picks[-1]]
            picked_scores_ok = all(abs(row[p] - row[q]) < 1e-4
                                   for p in picks for q in ref_picks)
            if not (sets_match or (picked_scores_ok and abs(row[picks[0]] - ref_cut) < 1e-4)):
                ok = False
                break
        checks["top2"] = ok
    checks["revision_out"] = ag.get("revision") == rev

    tot = sum(1 for v in checks.values() if v)
    if tot == len(checks):
        reward = 1.0
    elif checks.get("agent_runs") and checks.get("top2") and checks.get("similarity"):
        reward = 0.5
    else:
        reward = 0.0
    write(reward)
    print(checks, file=sys.stderr)
except Exception as e:
    write(0.0)
    print("verifier exception:", repr(e), file=sys.stderr)
PYEOF