#!/usr/bin/env bash
#
# umber-mantle verifier.
#
#  - checks the three /app deliverables produced for the visible fixture tree
#    and that the shipped example / input dataset / coexisting log are untouched
#  - re-runs the left-behind reusable solver /app/build.sh on each hidden input
#    tree (copied to a scratch dir) and checks the freshly generated outputs
#    against independently computed expectations (standard tools only)
#
# Always writes a numeric reward (0 or 1) to /logs/verifier/reward.txt.
set -euo pipefail
REWARD=0
mkdir -p /logs/verifier

fail() { echo "FAIL: $1"; echo 0 > /logs/verifier/reward.txt; exit 0; }
ok()  { echo "ok:   $1"; }

# Integrity digests of the VISIBLE fixture (variant 0) for the unmodified checks.
EXPECT_EXAMPLE=2bc6540f997668e4bc3ee777e441114bfc8987bfb63507e790facd9cbd47ed17
EXPECT_MAIN=37fbbf9aff6ff843123986d997b4783e4c7cc4a73ae3d263637ffea909ef9fec
EXPECT_LOG=d96c6e1f0f75c46ea0dd06969fa5991106a68ee8230a869d1aa3722bad65463e

# ---------------------------------------------------------------- oracles ----
# decode_oracle: uncompressed printer bytes (raw if already plaintext).
decode_oracle() {
  python3 - "$1" <<'PY'
import sys, gzip
b = open(sys.argv[1], "rb").read()
sys.stdout.buffer.write(gzip.decompress(b) if b[:2] == b"\x1f\x8b" else b)
PY
}

# bin_oracle: reassemble the binary from the hexdump inside archive.tar.gz.
# Independent implementation: token-stream over each line, take 2-hex tokens.
bin_oracle() {
  python3 - "$1" <<'PY'
import sys, tarfile, re
a = sys.argv[1]
with tarfile.open(a, "r:gz") as tf:
    txt = tf.extractfile("map.hex").read().decode()
out = bytearray()
for line in txt.splitlines():
    for tok in line.split():
        if re.fullmatch(r"[0-9a-fA-F]{2}", tok):
            out.append(int(tok, 16))
sys.stdout.buffer.write(bytes(out))
PY
}

# archive_ok: python validator -- shape, top-level path, exclusions, perms.
# $1 = path to out.tar.gz, $2 = root to compare main.csv bytes against.
archive_file_ok() {
  python3 - "$1" <<'PY'
import sys, tarfile, re
arc = sys.argv[1]
excl = re.compile(
    r"(^|/)(__pycache__|third_party|local)(/|$)"
    r"|(^|/)version\.manifest$"
    r"|\.o$|\.pyc$"
    r"|(^|/)credentials\.file$"
)
bad = []
names = []
with tarfile.open(arc, "r:gz") as t:
    for m in t:
        names.append(m.name)
        if not m.isdir() and not m.name.startswith("data/"):
            bad.append("entry outside data/: " + m.name)
        if not (m.mode & 0o004):
            bad.append("non-world-readable entry: " + m.name)
        if excl.search(m.name):
            bad.append("excluded entry present: " + m.name)
if "data/records/main.csv" not in names:
    bad.append("missing data/records/main.csv")
if bad:
    print("; ".join(bad)); sys.exit(1)
PY
}

# --------------------------------------------------------------------- checks
# check_tree ROOT : verify the three deliverables produced for ROOT.
check_tree() {
  local root="$1"
  local arc="$root/out.tar.gz"
  [ -f "$arc" ] || fail "($root) out.tar.gz missing"
  [ "$(head -c2 "$arc" | xxd -p)" = "1f8b" ] || fail "($root) out.tar.gz not gzip"
  archive_file_ok "$arc" || fail "($root) archive shape/exclusion"
  tar -xOzf "$arc" data/records/main.csv 2>/dev/null \
    | cmp -s - "$root/data/records/main.csv" \
    || fail "($root) archived main.csv != source"

  local pr; pr=$(ls "$root"/place/*.printer)
  [ -f "$root/decoded.raw" ] || fail "($root) decoded.raw missing"
  decode_oracle "$pr" | cmp -s - "$root/decoded.raw" \
    || fail "($root) decoded.raw mismatch"

  [ -f "$root/out.bin" ] || fail "($root) out.bin missing"
  bin_oracle "$root/payloads/archive.tar.gz" | cmp -s - "$root/out.bin" \
    || fail "($root) out.bin mismatch"
  ok "($root) out.tar.gz, decoded.raw, out.bin all valid"
}

# --------------------------------------------------------------- visible ----
[ -f /app/build.sh ] || fail "missing left-behind solver /app/build.sh"
check_tree /app

# Literal deliverable paths (executes-deliverable contract): every declared
# /app artifact must be present and fully validated on the visible tree. The
# full behavior (gzip shape, exclusions, byte-exact members, decoded printer,
# reassembled binary) is checked by check_tree /app above; these literal
# existence checks pin the exact declared paths.
for f in /app/out.tar.gz /app/decoded.raw /app/out.bin; do
  [ -f "$f" ] || fail "missing declared deliverable $f"
done
ok "literal deliverables present and validated under /app"

# integrity of the visible shipped fixtures (must be unmodified by the agent)
[ "$(sha256sum /app/data/scripts/etl_probe.py | cut -d' ' -f1)" = "$EXPECT_EXAMPLE" ] \
  || fail "visible: etl_probe.py was modified"
[ "$(sha256sum /app/data/records/main.csv | cut -d' ' -f1)" = "$EXPECT_MAIN" ] \
  || fail "visible: records/main.csv was modified"
[ "$(sha256sum /app/payloads/raw.log | cut -d' ' -f1)" = "$EXPECT_LOG" ] \
  || fail "visible: payloads/raw.log (coexisting log) was clobbered"
ok "visible: fixtures untouched"
REWARD=1

# ---------------------------------------------------------------- hidden ----
SRC=/tests/hidden
if [ ! -d "$SRC" ]; then
  echo "$REWARD" > /logs/verifier/reward.txt; exit 0
fi
n=0
for hd in "$SRC"/*; do
  [ -d "$hd" ] || continue
  n=$((n+1))
  name=$(basename "$hd")
  wd=$(mktemp -d /tmp/umber_hx_XXXX) || wd=/tmp/umber_hx_$name
  rm -rf "$wd"; cp -r "$hd" "$wd"

  main_dig=$(sha256sum "$wd/data/records/main.csv" | cut -d' ' -f1)
  ex_dig=$(sha256sum "$wd/data/scripts/etl_probe.py" | cut -d' ' -f1)
  log_dig=$(sha256sum "$wd/payloads/raw.log" | cut -d' ' -f1)

  bash /app/build.sh "$wd" >/dev/null 2>&1 \
    || fail "hidden $name: solver run failed"

  check_tree "$wd"

  [ "$(sha256sum "$wd/data/records/main.csv" | cut -d' ' -f1)" = "$main_dig" ] \
    || fail "hidden $name: main.csv modified by solver"
  [ "$(sha256sum "$wd/data/scripts/etl_probe.py" | cut -d' ' -f1)" = "$ex_dig" ] \
    || fail "hidden $name: etl_probe.py modified by solver"
  [ "$(sha256sum "$wd/payloads/raw.log" | cut -d' ' -f1)" = "$log_dig" ] \
    || fail "hidden $name: coexisting raw.log clobbered (archive wrongly expanded)"
  ok "hidden $name: outputs valid + inputs untouched"

  # no member of the archive may have been materialized beside its member
  if [ -f "$wd/payloads/big.bin" ]; then
    fail "hidden $name: big.bin materialized (archive fully expanded)"
  fi
  rm -rf "$wd"
done
[ "$n" -ge 3 ] || fail "expected >=3 hidden trees, saw $n"

echo "VERIFIER_OK"
echo "$REWARD" > /logs/verifier/reward.txt
exit 0