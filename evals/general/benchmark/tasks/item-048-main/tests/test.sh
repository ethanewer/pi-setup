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
    checks["top2"] = ag.get("top2") == top2_ref
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