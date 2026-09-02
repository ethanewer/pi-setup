#!/bin/bash
# Real oracle for marrow-vane: derive the machine profile from the datasheet,
# write the emulate.sh runner, and RUN it on the shipped image to produce
# /app/legacy/output.txt. Never reads /tests.
set -eu

PROFILE="/app/bench/coursefix.profile.json"
RUNNER="/app/legacy/emulate.sh"

# ---- 1. Machine profile: Corvid-8 datasheet says 64 KiB RAM (65536 bytes,
# memory_kib = 64), EPROM base 0x0200 = 512 (load_address), execution begins
# at the load address (entry = 512), SDATA 0xF000 = 61440.
cat > "$PROFILE" <<'JSON'
{
  "memory_kib": 64,
  "load_address": 512,
  "entry": 512,
  "serial_out_address": 61440
}
JSON

# ---- 2. Runner: drive the installed generic emulator host; three CLI modes.
cat > "$RUNNER" <<'SH'
#!/bin/bash
set -u
EMU="/app/bench/corvid-emu"
PROFILE="/app/bench/coursefix.profile.json"
DEFAULT_ROM="/app/legacy/course_fix.bin"
DEFAULT_OUT="/app/legacy/output.txt"

case $# in
  0) ROM="$DEFAULT_ROM"; OUT="$DEFAULT_OUT" ;;
  1) ROM="$1"; OUT="$DEFAULT_OUT" ;;
  2) ROM="$1"; OUT="$2" ;;
  *) echo "usage: emulate.sh [IMAGE.bin [OUTPUT.txt]]" >&2; exit 2 ;;
esac

rm -f "$OUT"
"$EMU" --profile "$PROFILE" --rom "$ROM" --serial-out "$OUT"
exit 0
SH
chmod +x "$RUNNER"

# ---- 3. Actually run the shipped legacy image to capture its output.
"$RUNNER"

echo "solve.sh done -> $PROFILE $RUNNER /app/legacy/output.txt"
ls -l "$PROFILE" "$RUNNER" /app/legacy/output.txt
