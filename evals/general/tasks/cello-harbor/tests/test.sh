#!/bin/bash
# Verifier for cello-harbor: checks the visible deliverables, ENFORCES the
# no-modify rule on /app/stream.json, and EXECUTES /app/solve.py on the visible
# case plus every hidden case in /tests/hidden, validating the six structural
# constraints of the relay-scheduling contract. Writes REWARD (0/1) to
# /logs/verifier/reward.txt.
set -u

mkdir -p /logs/verifier
reward=0

PRISTINE_STREAM_SHA="08edb08007a7c2433340ce1e3956e0a4c8c51ff7e766c2c395c2f6b694d9ab9c"

no_modify_broken=0
if [ ! -f /app/stream.json ]; then
    echo "no-modify: /app/stream.json missing" >&2
    no_modify_broken=1
else
    actual="$(sha256sum /app/stream.json | awk '{print $1}')"
    if [ "$actual" != "$PRISTINE_STREAM_SHA" ]; then
        echo "no-modify: /app/stream.json was modified" >&2
        no_modify_broken=1
    fi
fi

python3 - "$no_modify_broken" <<'PY'
import json, os, subprocess, sys

SOLVE = "/app/solve.py"
no_modify_broken = int(sys.argv[1])
failures = []


def validate(stream, plan, label):
    """Check every hard constraint of the scheduling contract."""
    try:
        budget = stream["budget"]
        sector = budget["sector"]
        max_seg = budget["max_segment_ms"]
        win_cap = budget["window_ms"]
        win_budget = budget["windows"]
        chunks = stream["chunks"]
    except Exception as e:
        return ["%s: unreadable stream/budget: %s" % (label, e)]

    if not isinstance(plan, dict):
        return ["%s: plan is not a JSON object" % label]
    if set(plan.keys()) != {"budget", "windows"}:
        return ["%s: plan keys must be exactly {budget, windows}, got %s"
                % (label, sorted(plan.keys()))]
    if plan["budget"] != budget:
        return ["%s: budget not copied through unchanged" % label]
    windows = plan["windows"]
    if not isinstance(windows, list):
        return ["%s: windows must be a list" % label]
    if len(windows) > win_budget:
        return ["%s: %d windows exceeds budget %d"
                % (label, len(windows), win_budget)]

    order = []
    seg_ids, win_ids = set(), set()
    by_id = {c["id"]: c for c in chunks}
    if len(by_id) != len(chunks):
        return ["%s: input chunk ids are not unique (bad case)" % label]

    for widx, w in enumerate(windows):
        if not isinstance(w, dict) or set(w.keys()) != {"window_id", "ms", "segments"}:
            return ["%s: window %d keys must be {window_id, ms, segments}" % (label, widx)]
        if w["window_id"] in win_ids:
            return ["%s: duplicate window_id %r" % (label, w["window_id"])]
        win_ids.add(w["window_id"])
        segs = w["segments"]
        if not isinstance(segs, list) or len(segs) == 0:
            return ["%s: window %d must hold at least one segment" % (label, widx)]
        total = 0
        for sidx, s in enumerate(segs):
            if not isinstance(s, dict) or set(s.keys()) != {"segment_id", "chunks", "ms"}:
                return ["%s: segment %d/%d keys must be {segment_id, chunks, ms}"
                        % (label, widx, sidx)]
            if s["segment_id"] in seg_ids:
                return ["%s: duplicate segment_id %r" % (label, s["segment_id"])]
            seg_ids.add(s["segment_id"])
            ids = s["chunks"]
            if not isinstance(ids, list) or len(ids) == 0:
                return ["%s: segment %d/%d must hold >=1 chunk" % (label, widx, sidx)]
            try:
                s_ms = sum(int(by_id[cid]["ms"]) for cid in ids)
            except KeyError as e:
                return ["%s: segment references unknown chunk id %s" % (label, e)]
            if s_ms != s["ms"]:
                return ["%s: segment %d/%d ms=%r != sum %d"
                        % (label, widx, sidx, s["ms"], s_ms)]
            if s_ms <= 0 or s_ms % sector != 0:
                return ["%s: segment %d/%d ms=%d not a positive multiple of sector %d"
                        % (label, widx, sidx, s_ms, sector)]
            if s_ms > max_seg:
                return ["%s: segment %d/%d ms=%d exceeds max_segment_ms %d"
                        % (label, widx, sidx, s_ms, max_seg)]
            total += s_ms
            for cid in ids:
                order.append((cid, widx))
        if total != w["ms"]:
            return ["%s: window %d ms=%r != segment sum %d" % (label, widx, w["ms"], total)]
        if total > win_cap:
            return ["%s: window %d ms=%d exceeds window_ms %d" % (label, widx, total, win_cap)]

    got_ids = [cid for cid, _ in order]
    want_ids = [c["id"] for c in chunks]
    if len(got_ids) != len(set(got_ids)):
        return ["%s: duplicated chunk ids in plan" % label]
    if sorted(got_ids) != sorted(want_ids):
        missing = set(want_ids) - set(got_ids)
        extra = set(got_ids) - set(want_ids)
        return ["%s: id set mismatch (missing=%s extra=%s)"
                % (label, sorted(missing), sorted(extra))]
    if got_ids != want_ids:
        return ["%s: arrival order not preserved" % label]
    for cid, widx in order:
        due = by_id[cid]["due"]
        if widx > due:
            return ["%s: chunk %s in window %d misses deadline %d"
                    % (label, cid, widx, due)]
    return []


def run_case(stream_path, label):
    out = "/tmp/cello_harbor_verify_plan.json"
    if os.path.exists(out):
        os.remove(out)
    try:
        r = subprocess.run(
            [sys.executable, SOLVE, stream_path, out],
            capture_output=True, text=True, timeout=120,
        )
    except subprocess.TimeoutExpired:
        return ["%s: solve.py timed out" % label]
    if r.returncode != 0:
        return ["%s: solve.py exited %d: %s" % (label, r.returncode, r.stderr[-200:])]
    if not os.path.exists(out):
        return ["%s: solve.py produced no output" % label]
    try:
        with open(out) as f:
            plan = json.load(f)
        with open(stream_path) as f:
            stream = json.load(f)
    except Exception as e:
        return ["%s: unreadable json: %s" % (label, e)]
    return validate(stream, plan, label)


if no_modify_broken:
    failures.append("visible input /app/stream.json modified or missing (no-modify rule)")

if not os.path.isfile(SOLVE):
    failures.append("missing /app/solve.py")
else:
    # visible case: execute solve.py on the live supplied input
    if os.path.isfile("/app/stream.json"):
        failures.extend(run_case("/app/stream.json", "visible"))
    else:
        failures.append("visible input missing")

    # visible-case deliverable: /app/plan.json must exist and be a valid
    # schedule for the visible stream
    if os.path.isfile("/app/plan.json"):
        try:
            with open("/app/plan.json") as f:
                plan = json.load(f)
            with open("/app/stream.json") as f:
                stream = json.load(f)
            failures.extend(validate(stream, plan, "visible-deliverable"))
        except Exception as e:
            failures.append("plan.json unreadable: %s" % e)
    else:
        failures.append("missing /app/plan.json")

    # hidden cases: genuinely distinct inputs, constraint-validated
    hidden_dir = "/tests/hidden"
    if os.path.isdir(hidden_dir):
        cases = sorted(os.listdir(hidden_dir))
        if not cases:
            failures.append("no hidden cases present")
        for c in cases:
            stream_path = os.path.join(hidden_dir, c, "stream.json")
            if not os.path.isfile(stream_path):
                failures.append("hidden '%s' malformed (no stream.json)" % c)
                continue
            failures.extend(run_case(stream_path, "hidden:%s" % c))
    else:
        failures.append("no hidden cases directory")

print("verify failures:", failures)
sys.exit(1 if failures else 0)
PY

if [ $? -eq 0 ]; then reward=1; fi
echo "$reward" > /logs/verifier/reward.txt
exit 0
