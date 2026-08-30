#!/usr/bin/env bash
#
# vine-pier verifier.  Boots from a pristine image (or after the agent) and
# independently re-executes every deliverable: compiles and runs the pure-C
# reader against the shipped and a hidden checkpoint/vocab, and re-runs the
# greedy generator, the speculative draft-and-verify loop, and the
# revision-pinned retrieval on fresh hidden inputs, and reloads the fitted
# pickle + two-place params JSON.  Every result is compared to an independent
# reference in tests/ref_model.py.  Writes a numeric reward.
set -u
mkdir -p /logs/verifier
ok=1
fail(){ echo "VERIFY-FAIL: $*" >&2; ok=0; }
REFLIB=/tests/ref_model.py
MODEL=/app/data/checkpoint.ckpt

[ -f "$REFLIB" ] || { echo "no ref_model.py; reward=0" >&2; echo 0 > /logs/verifier/reward.txt; exit 0; }

# ---------------------------------------------------------------------------
# A. deliverables present
# ---------------------------------------------------------------------------
for f in ckpt_reader.c ckpt_reader generate.py greedy_out.json \
         speculative.py spec_out.json retrieve.py ranks.json \
         model.pkl params.json; do
  [ -f "/app/$f" ] || fail "missing deliverable /app/$f"
done
[ -x /app/ckpt_reader ] || fail "deliverable /app/ckpt_reader not executable"

# ---------------------------------------------------------------------------
# B. pure-C reader: compiles and matches the reference dump on both the shipped
#    and hidden checkpoints (hidden has a different vocabulary).
# ---------------------------------------------------------------------------
if ! gcc -O2 -o /tmp/ckpt_reader /app/ckpt_reader.c >/tmp/gcc.log 2>&1; then
  fail "pure-C reader did not compile"
else
  for ck_path in "$MODEL" /tests/hidden/alt.ckpt; do
    if [ "$ck_path" = "$MODEL" ]; then voc=/app/data/vocab.txt; else voc=/tests/hidden/alt.vocab; fi
    if ! /tmp/ckpt_reader "$ck_path" "$voc" > /tmp/reader.out 2>/tmp/reader.err; then
      fail "pure-C reader exited non-zero on $ck_path"
    else
      python3 - "$ck_path" "$voc" /tmp/reader.out <<'PY' || fail "reader dump mismatch on $ck_path"
import sys
sys.path.insert(0, "/tests")
import ref_model as R
ck, voc, gotp = sys.argv[1], sys.argv[2], sys.argv[3]
exp = "\n".join(R.reader_dump(ck, voc)) + "\n"
got = open(gotp).read()
assert got == exp, "byte-level dump differs (got %d lines, want %d)" % (
    len(got.splitlines()), exp.count("\n"))
PY
    fi
  done
fi

# ---------------------------------------------------------------------------
# C. greedy target-sequence generation, re-run on fresh hidden prompts.
# ---------------------------------------------------------------------------
run_greedy(){
  name=$1; prompt=$2
  python3 /app/generate.py --model "$MODEL" --prompt "$prompt" \
    --out /tmp/greed_$name.json >/dev/null 2>/tmp/generate.err \
    || { fail "generate.py failed on $name"; return; }
  python3 - "$prompt" /tmp/greed_$name.json <<'PY' || fail "greedy mismatch on $name"
import sys, json
sys.path.insert(0, "/tests")
import ref_model as R
prompt_s, out = sys.argv[1], sys.argv[2]
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
prompt = [int(x) for x in prompt_s.split(",") if x != ""]
W, B = ck["tensors"]["W"], ck["tensors"]["B"]
exp_full = R.greedy(prompt, W, B, ck["max_gen"])
got = json.load(open(out))
assert got["revision"] == ck["rev"], "revision not pinned"
assert got["max_gen"] == ck["max_gen"]
assert got["prompt"] == prompt
assert got["continuation"] == exp_full[len(prompt):], "continuation differs"
assert got["full"] == exp_full, "full sequence differs"
PY
}
run_greedy a "11,4"
run_greedy b "2,2"
run_greedy c "30,1,5"

# ---------------------------------------------------------------------------
# D. speculative draft-and-verify against a target sequence.  Hidden combos
#    include a draft-greedy target that verifies (all accepts), short targets,
#    and single-token drafts.  The expected q counts are recomputed by ref.
# ---------------------------------------------------------------------------
# an accept-everything target: target model greedily predicted for prefix [2,5]
python3 - <<'PY' > /tmp/spec_draft_tgt.txt
import sys
sys.path.insert(0, "/tests")
import ref_model as R
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
D, B = ck["tensors"]["D"], ck["tensors"]["B"]
seq = [2, 5]
for _ in range(9):
    seq.append(int(D[seq[-2], seq[-1]].argmax()))
print(",".join(str(x) for x in seq[2:]))
PY
# a short (2-token) ordinary greedy target
python3 - <<'PY' > /tmp/spec_short_tgt.txt
import sys
sys.path.insert(0, "/tests")
import ref_model as R
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
W, B = ck["tensors"]["W"], ck["tensors"]["B"]
full = R.greedy([7, 11], W, B, 2)
print(",".join(str(x) for x in full[2:]))
PY

run_spec(){
  name=$1; prefix=$2; target=$3; k=$4
  python3 /app/speculative.py --model "$MODEL" --prefix "$prefix" --target "$target" \
     --draft "$k" --out /tmp/spec_$name.json >/dev/null 2>/tmp/spec.err \
     || { fail "speculative.py failed on $name"; return; }
  python3 - "$prefix" "$target" "$k" /tmp/spec_$name.json <<'PY' || fail "spec mismatch on $name"
import sys, json
sys.path.insert(0, "/tests")
import ref_model as R
ps, ts, ks, out = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
prefix = [int(x) for x in ps.split(",") if x != ""]
target = [int(x) for x in ts.split(",") if x != ""]
k = int(ks)
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
D, B = ck["tensors"]["D"], ck["tensors"]["B"]
seq, extra = R.run_spec(prefix, target, D, B, k)
got = json.load(open(out))
assert got["revision"] == ck["rev"]
assert got["draft_len"] == k
assert got["result"] == seq, "final context differs"
assert got["n_drafted"] == extra["n_drafted"], "drafted count differs"
assert got["n_accepted"] == extra["n_accepted"], "accepted count differs"
assert got["blocks"] == extra["blocks"], "block-by-block verdict differs"
# consistency: does the reported multi-step extension actually reach prefix+target?
stop = len(prefix) + len(target)
pos = len(prefix)
for blk in got["blocks"]:
    assert blk["start"] == pos, "context not extended monotonically"
    assert blk["accepted"] <= len(blk["draft"])
    pos += blk["accepted"]
    if blk["rejected"] and pos < stop:
        pos += 1
assert pos == stop, "final length off-by-one (%d != %d)" % (pos, stop)
PY
}
run_spec a "8,13" "3,22,6,11,30,7,7,24" 3
run_spec b "2,5" "$(cat /tmp/spec_draft_tgt.txt)" 3
run_spec c "7,11" "$(cat /tmp/spec_short_tgt.txt)" 1
run_spec d "29,18" "4,9,4,9" 1

# ---------------------------------------------------------------------------
# E) revision-pinned retrieval + cosine ranking (hidden corpora, incl. an empty
#    doc token list and an empty query).
# ---------------------------------------------------------------------------
run_retr(){
  name=$1; docs=$2; query=$3
  python3 /app/retrieve.py --model "$MODEL" --docs "$docs" --query "$query" \
     --out /tmp/rank_$name.json >/dev/null 2>/tmp/ret.err \
     || { fail "retrieve.py failed on $name"; return; }
  python3 - "$docs" "$query" /tmp/rank_$name.json <<'PY' || fail "retrieval mismatch on $name"
import sys, json
sys.path.insert(0, "/tests")
import ref_model as R
docs_s, query_s, out = sys.argv[1], sys.argv[2], sys.argv[3]
docs = [[int(x) for x in d.split(",") if x != ""] for d in docs_s.split(";")]
query = [int(x) for x in query_s.split(",") if x != ""]
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
exp_rank = [{"doc": i, "position": p, "cosine": round(c, 6)}
            for p, (i, c) in enumerate(R.pretrieve(ck["tensors"]["emb"], docs, query), 1)]
got = json.load(open(out))
assert got["revision"] == ck["rev"], "revision not pinned"
assert got["embedding_dim"] == ck["d_emb"]
assert got["selected"] == exp_rank[0]["doc"], "selected differs"
assert got["fifth"] == (exp_rank[4]["doc"] if len(exp_rank) >= 5 else None), "fifth differs"
assert got["rank"] == exp_rank, "ranking/cosine differs"
PY
}
run_retr r1 "5,1,1;5,7;0,3;12,6,4;6,0" "2,4"
run_retr r2 "4,4;4,1;3,3" "2,2"
run_retr r3 "7;;5,1,0" "2,2"

# ---------------------------------------------------------------------------
# F) fitted model pickle
# ---------------------------------------------------------------------------
python3 - <<'PY' || fail "model.pkl not a valid fitted-model pickle"
import pickle
import sys
import numpy as np
sys.path.insert(0, "/tests")
import ref_model as R
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
m = pickle.load(open("/app/model.pkl", "rb"))
for key in ("W", "b", "revision", "fitted", "vocab_size"):
    assert key in m, "pickle missing " + key
assert m["fitted"] is True
assert m["revision"] == ck["rev"]
assert m["vocab_size"] == ck["V"]
assert m["W"].shape == ck["tensors"]["W"].shape
assert m["b"].shape == ck["tensors"]["B"].shape
assert np.allclose(m["W"], ck["tensors"]["W"], atol=1e-4), "W not persisted"
assert np.allclose(m["b"], ck["tensors"]["B"], atol=1e-4), "b not persisted"
PY

# ---------------------------------------------------------------------------
# G) two-peak params JSON
# ---------------------------------------------------------------------------
python3 - <<'PY' || fail "params.json layout or values invalid"
import json
import sys
import numpy as np
sys.path.insert(0, "/tests")
import ref_model as R
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
p = json.load(open("/app/params.json"))
assert set(p.keys()) == {"model", "fitted", "vocab_size", "revision", "peaks"}, set(p.keys())
assert set(p["peaks"].keys()) == {"W", "B"}, set(p["peaks"].keys())
assert p["fitted"] is True
assert p["revision"] == ck["rev"]
assert p["vocab_size"] == ck["V"]
W = np.asarray(p["peaks"]["W"], dtype="float64")
B = np.asarray(p["peaks"]["B"], dtype="float64")
assert W.shape == ck["tensors"]["W"].shape
assert B.shape == ck["tensors"]["B"].shape
assert np.allclose(W, ck["tensors"]["W"].astype("float64"), atol=1e-4), "W peak mismatch"
assert np.allclose(B, ck["tensors"]["B"].astype("float64"), atol=1e-4), "B peak mismatch"
PY

# ---------------------------------------------------------------------------
# H) visible report JSON deliverables must be genuine: re-run each program on
#    the exact arguments that produced it and require the shipped file to match.
# ---------------------------------------------------------------------------
python3 /app/generate.py --model "$MODEL" --prompt 2,4 \
  --out /tmp/vis_greedy.json >/dev/null 2>/tmp/vis_greedy.err \
  || fail "generate.py failed producing visible report"
python3 -c '
import json
assert json.load(open("/app/greedy_out.json")) == json.load(open("/tmp/vis_greedy.json")), "greedy_out.json differs"
' || fail "greedy_out.json inconsistent with generator"

python3 - <<'PY' > /tmp/vis_spec_tgt.txt
import sys
sys.path.insert(0, "/tests")
import ref_model as R
ck = R.load_ckpt("/app/data/checkpoint.ckpt")
W, B = ck["tensors"]["W"], ck["tensors"]["B"]
seq = R.greedy([1, 2], W, B, ck["max_gen"])
print(",".join(str(x) for x in seq[2:]))
PY
python3 /app/speculative.py --model "$MODEL" --prefix "1,2" \
  --target "$(cat /tmp/vis_spec_tgt.txt)" --draft 3 \
  --out /tmp/vis_spec.json >/dev/null 2>/tmp/vis_spec.err \
  || fail "speculative.py failed producing visible report"
python3 -c '
import json
assert json.load(open("/app/spec_out.json")) == json.load(open("/tmp/vis_spec.json")), "spec_out.json differs"
' || fail "spec_out.json inconsistent with speculative loop"

python3 /app/retrieve.py --model "$MODEL" \
  --docs "1,1,9;5,4;6,0;2,6,3;1,9,9" --query "2,4" \
  --out /tmp/vis_rank.json >/dev/null 2>/tmp/vis_rank.err \
  || fail "retrieve.py failed producing visible report"
python3 -c '
import json
assert json.load(open("/app/ranks.json")) == json.load(open("/tmp/vis_rank.json")), "ranks.json differs"
' || fail "ranks.json inconsistent with retriever"

# ---------------------------------------------------------------------------
# reward
# ---------------------------------------------------------------------------
[ "$ok" -eq 1 ] && reward=1 || reward=0
echo "$reward" > /logs/verifier/reward.txt
echo "reward=$reward" >&2
exit 0