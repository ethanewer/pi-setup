#!/usr/bin/env bash
# tundra-keystone verifier: executes every deliverable, including on hidden
# inputs beneath /tests/hidden, and writes a numeric reward.
set -uo pipefail

RE=/logs/verifier/reward.txt
LOG=/logs/verifier/verify.log
SCRATCH=/logs/verifier/scratch
mkdir -p "$(dirname "$RE")" "$SCRATCH"

CH=/tests/check_helpers.py
PY=python3
r=1

note(){ echo "$*"; echo "$*" >> "$LOG"; }

# Every deliverable must exist (this is what fails the negative control).
for f in pipeline_parallel.py grad_exchange.npz async_pool.py async_log.txt mp_entry.py; do
  if [ ! -f "/app/$f" ]; then
    note "missing deliverable /app/$f"
    echo "0" > "$RE"
    exit 0
  fi
done

# 1) default (oracle-produced) artifacts
if ! $PY "$CH" pipeline /app/grad_exchange.npz 4 8 16 3; then r=0; note "default grad_exchange failed"; fi
if ! $PY "$CH" async /app/async_log.txt 6 3 3; then r=0; note "default async_log failed"; fi
if ! $PY /app/mp_entry.py > "$SCRATCH/mp_default.out" 2>&1; then r=0; note "default mp run failed"; fi
if ! $PY "$CH" mp "$SCRATCH/mp_default.out"; then r=0; note "default mp check failed"; fi

# documented contract: `python3 -c "import mp_entry"` does nothing (no output, no pool, no hang)
if ! (cd /app && timeout 30 $PY -c "import mp_entry" > "$SCRATCH/mp_import.out" 2>&1); then
  r=0; note "mp import failed or hung (must be side-effect free)"
elif [ -s "$SCRATCH/mp_import.out" ]; then
  r=0; note "mp import produced output (import must do nothing)"
fi

# 2. hidden pipeline configs: re-check the partition/gradient exchange on fresh world/rank/shape ----
for cfg in /tests/hidden/pipeline_*.json; do
  [ -e "$cfg" ] || continue
  W=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['world_w'])" "$cfg")
  L=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['num_layers'])" "$cfg")
  D=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['d'])" "$cfg")
  B=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['batch'])" "$cfg")
  out="$SCRATCH/p_${W}_${L}_${D}_${B}.npz"
  if ! $PY /app/pipeline_parallel.py --world-size "$W" --layers "$L" --d "$D" --batch "$B" --out "$out"; then
    r=0; note "hidden pipeline run failed $cfg"; continue
  fi
  if ! $PY "$CH" pipeline "$out" "$W" "$L" "$D" "$B"; then r=0; note "hidden pipeline check failed $cfg"; fi
done

# 3. hidden async job sets: re-run the scheduler against fresh workloads ---------------------------------
for cfg in /tests/hidden/async_*.json; do
  [ -e "$cfg" ] || continue
  n=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['n'])" "$cfg")
  cap=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['cap'])" "$cfg")
  trg=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['trigger'])" "$cfg")
  out="$SCRATCH/hidden_${n}_${cap}_${trg}.json"
  if ! $PY /app/async_pool.py --jobs "$n" --cap "$cap" --trigger "$trg" --out "$out"; then
    r=0; note "hidden async run failed $cfg"; continue
  fi
  if ! $PY "$CH" async "$out" "$n" "$cap" "$trg"; then r=0; note "hidden async check failed $cfg"; fi
done

# 4. hidden mp: re-execute the multiprocessing entry with a different pool size --------------------------------
for cfg in /tests/hidden/mp_*.json; do
  [ -e "$cfg" ] || continue
  P=$("$PY" -c "import json,sys;print(json.load(open(sys.argv[1]))['procs'])" "$cfg")
  if ! $PY /app/mp_entry.py "$P" > "$SCRATCH/mp_hidden.out" 2>&1; then r=0; note "mp hidden run failed $cfg"; continue; fi
  if ! $PY "$CH" mp "$SCRATCH/mp_hidden.out"; then r=0; note "mp hidden check failed $cfg"; fi
done

echo "r = $r"
echo "$r" > "$RE"
exit 0