#!/bin/bash
# Verifier for the jade-shard task.
#
# executes-deliverable. /app/reshard.py must split a row-major tensor record
# into exactly three contiguous, as-even-as-possible shards plus a manifest,
# and must be able to reassemble and verify the tensor (join). The verifier
# runs the tool on the visible /app/tensor.json and on hidden inputs under
# /tests/hidden, independently recomputing the expected even split and checksum
# (so it is not tied to the oracle's coding style). Malformed hidden inputs must
# be rejected with a non-zero exit.
#
# Always writes a numeric reward to /logs/verifier/reward.txt.
set -u
mkdir -p /logs/verifier
reward=0
ok=1

if [ ! -f /app/reshard.py ]; then
    echo "missing deliverable /app/reshard.py" >&2
    ok=0
fi

# run_tensor_check <input.json>
# Drives shard -> independent structural check -> join -> reconstruction compare
# for a valid tensor. Prints the outdir on success; non-zero on any failure.
run_tensor_check() {
    local inp="$1"
    local out; out=$(mktemp -d)
    rm -rf "$out"; mkdir -p "$out"
    if ! python3 /app/reshard.py shard --input "$inp" --outdir "$out" >/tmp/rs.log 2>&1; then
        echo "shard failed on $inp: $(tail -1 /tmp/rs.log)" >&2
        return 1
    fi
    python3 - "$inp" "$out" <<'PY'
import json, os, subprocess, sys, hashlib
inp, out = sys.argv[1], sys.argv[2]

def csum(v):
    return hashlib.sha256(json.dumps(v, separators=(",", ":")).encode()).hexdigest()

obj = json.load(open(inp))
shape, values = obj["shape"], obj["values"]
n = 1
for d in shape:
    n *= d
if len(values) != n:
    print("internal: input count mismatch", inp); sys.exit(2)

# independent recomputation of the documented even split
base, rem = divmod(n, 3)
counts = [base + (1 if i < rem else 0) for i in range(3)]
offsets = []
acc = 0
for c in counts:
    offsets.append(acc)
    acc += c

for i in range(3):
    sh = json.load(open(os.path.join(out, "shard-%d.json" % i)))
    if sh.get("shard_index") != i:
        print("shard_index wrong for", i); sys.exit(2)
    if sh.get("offset") != offsets[i] or sh.get("count") != counts[i]:
        print("offset/count wrong for shard", i); sys.exit(2)
    if sh.get("values") != values[offsets[i]:offsets[i] + counts[i]]:
        print("values slice wrong for shard", i); sys.exit(2)

man = json.load(open(os.path.join(out, "manifest.json")))
if man.get("shape") != shape or man.get("element_count") != n or man.get("num_shards") != 3:
    print("manifest shape/count/num_shards wrong"); sys.exit(2)
if man.get("checksum") != csum(values):
    print("checksum mismatch"); sys.exit(2)
if man.get("shards") != [{"index": i, "offset": offsets[i], "count": counts[i]} for i in range(3)]:
    print("manifest shards table wrong"); sys.exit(2)

# join must reconstruct the input byte-identical
r = subprocess.run(["python3", "/app/reshard.py", "join",
                    "--manifest", os.path.join(out, "manifest.json"),
                    "--outdir", out], capture_output=True)
if r.returncode != 0:
    print("join failed (rc=%d) for %s: %s" % (r.returncode, inp, r.stderr.strip().decode()[-150:])); sys.exit(2)
rec = json.load(open(os.path.join(out, "reconstructed.json")))
if rec != obj:
    print("reconstructed != original for", inp); sys.exit(2)
PY
    [ $? -eq 0 ] || return 1
    echo "$out"
}

# run_reject <input.json>: the tool MUST refuse malformed input (non-zero exit)
run_reject() {
    local inp="$1"
    local out; out=$(mktemp -d)
    rm -rf "$out"; mkdir -p "$out"
    if python3 /app/reshard.py shard --input "$inp" --outdir "$out" >/tmp/rr.log 2>&1; then
        echo "expected shard to reject malformed input $inp but it succeeded" >&2
        return 1
    fi
    return 0
}

[ "$ok" = 1 ] || { echo "$reward" > /logs/verifier/reward.txt; echo "REWARD=$reward"; exit 0; }

# 1) Visible case /app/tensor.json + require manifest to equal expected.json
vout=""
vout=$(run_tensor_check /app/tensor.json) || ok=0
if [ "$ok" = 1 ]; then
    python3 - "$vout/manifest.json" /tests/expected.json <<'PY'
import json, sys
got = json.load(open(sys.argv[1]))
want = json.load(open(sys.argv[2]))
sys.exit(0 if got == want else 1)
PY
    if [ $? -ne 0 ]; then
        echo "visible manifest does not match tests/expected.json" >&2
        ok=0
    fi
fi

# 2) Hidden valid cases
if [ "$ok" = 1 ]; then
    hcount=0
    for d in /tests/hidden/ok_*; do
        [ -d "$d" ] || continue
        if run_tensor_check "$d/input.json" >/dev/null; then
            hcount=$((hcount + 1))
        else
            echo "hidden valid case failed: $d" >&2
            ok=0
        fi
    done
    [ "$hcount" -ge 2 ] || { echo "too few hidden valid cases" >&2; ok=0; }
fi

# 3) Hidden malformed cases must be rejected
if [ "$ok" = 1 ]; then
    mcount=0
    for d in /tests/hidden/bad_*; do
        [ -d "$d" ] || continue
        if run_reject "$d/input.json"; then
            mcount=$((mcount + 1))
        else
            echo "hidden malformed case was accepted: $d" >&2
            ok=0
        fi
    done
    [ "$mcount" -ge 1 ] || { echo "no hidden malformed cases found" >&2; ok=0; }
fi

[ "$ok" = 1 ] && reward=1
echo "$reward" > /logs/verifier/reward.txt
echo "REWARD=$reward"
exit 0