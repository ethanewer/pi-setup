#!/bin/bash
# brisk-anchor verifier. Executes every deliverable (each /app program) on the
# visible fixtures and on every hidden input set, then compares against goldens
# with helpers/verify_all.py. Writes a numeric reward to /logs/verifier/reward.txt.
set -uo pipefail

V=/logs/verifier
mkdir -p "$V"

fail() { echo "VERIFIER: $1" >&2; echo "$2" > "$V/reward.txt"; exit 0; }

# ---- prerequisites: all deliverables must exist ----
for d in \
    /app/ocr.py /app/invoice-labels.json /app/field-map.py /app/field-map.json \
    /app/retrieval-stats.json /app/chess-read.py /app/positions.json \
    /app/extract.py /app/profiles.json; do
    [ -f "$d" ] || fail "missing deliverable $d" 0
done

# ---- execute each deliverable against the visible fixtures ----
python3 /app/ocr.py /app/scans /tmp/ocr_visible.json \
    || fail "ocr.py failed on visible scans" 0
python3 /app/field-map.py -f /app/fields -c /app/chunks -m /tmp/fm_visible.json -s /tmp/st_visible.json \
    || fail "field-map.py failed on visible corpus" 0
python3 /app/chess-read.py /app/boards /tmp/chess_visible.json \
    || fail "chess-read.py failed on visible boards" 0
python3 /app/extract.py /app/docs /tmp/profiles_visible.json \
    || fail "extract.py failed on visible docs" 0

# ---- execute against every hidden input set ----
python3 /app/ocr.py /tests/hidden/ocr/scan_a /tmp/ocr_scan_a.json \
    || fail "ocr.py failed on hidden scan_a" 0
python3 /app/ocr.py /tests/hidden/ocr/scan_b_edge /tmp/ocr_scan_b_edge.json \
    || fail "ocr.py failed on hidden scan_b_edge" 0
python3 /app/field-map.py -f /tests/hidden/fieldmap/set_a/fields -c /tests/hidden/fieldmap/set_a/chunks \
        -m /tmp/fm_set_a.json -s /tmp/st_set_a.json \
    || fail "field-map.py failed on hidden set_a" 0
python3 /app/field-map.py -f /tests/hidden/fieldmap/set_b/fields -c /tests/hidden/fieldmap/set_b/chunks \
        -m /tmp/fm_set_b.json -s /tmp/st_set_b.json \
    || fail "field-map.py failed on hidden set_b" 0
python3 /app/chess-read.py /tests/hidden/chess /tmp/chess_hidden.json \
    || fail "chess-read.py failed on hidden boards" 0
python3 /app/extract.py /tests/hidden/profiles /tmp/profiles_hidden.json \
    || fail "extract.py failed on hidden docs" 0

# ---- independent recomputation check for the visible field-map deliverable ----
# (the deliverable JSON files are also validated in verify_all.py)
python3 /tests/helpers/verify_all.py
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "$rc" >/dev/null
    echo 1 > "$V/reward.txt"
    echo "VERIFIER: all checks passed"
else
    echo 0 > "$V/reward.txt"
    echo "VERIFIER: checks failed" >&2
fi
exit 0