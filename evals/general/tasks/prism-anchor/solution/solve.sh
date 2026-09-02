#!/bin/bash
# prism-anchor oracle. Does the real work in a pristine container:
#   1) writes the three program deliverables into /app
#   2) configures the shared area & auth, restores script permissions
#   3) recovers the deleted-but-open telemetry source via /proc
#   4) verifies the normalize() implementation against the example set
#   5) runs the targeted suite, profiles with cProfile
#   6) assembles /app/dump.txt (the evidence bundle)
# Never reads /tests and never cats a precomputed answer.
set -e

# ---------------------------------------------------------------- configure.sh
cat > /app/configure.sh <<'SH'
#!/bin/bash
# prism-anchor configure.sh
# Usage: configure.sh [SHARED_DIR [GROUP]]
#   SHARED_DIR defaults to /srv/prism ; GROUP defaults to anchorline
# Idempotent. Denies non-members, preserves group execute via ACL mask,
# re-enables ssh password auth, and removes stale lifecycle files.
set -u
SHARE="${1:-/srv/prism}"
GROUP="${2:-anchorline}"

if [ -f "$SHARE" ]; then
  echo "configure: $SHARE is a regular file; aborting" >&2
  exit 1
fi

# base / default columns: no 'other' access anywhere in the hierarchy
mkdir -p "$SHARE"
chgrp "$GROUP" "$SHARE"
chmod 0770 "$SHARE"

# ACL mask rwx so script execute is never stripped; grant only to the group
setfacl -m g:"$GROUP":rwx,m::rwx "$SHARE" 2>/dev/null || true

# every subdirectory becomes groups-only too (no 'other' bits anywhere)
for d in "$SHARE"/*/ "$SHARE"/.[!.]*/; do
  if [ -d "$d" ]; then
    chgrp "$GROUP" "$d"
    chmod 0770 "$d"
    setfacl -m g:"$GROUP":rwx,m::rwx "$d" 2>/dev/null || true
  fi
done

# script area: preserve execute for group members (default ACL mask is rwx)
BIN="$SHARE/bin"
if [ -d "$BIN" ]; then
  setfacl -m g::rwx,m::rwx,g:"$GROUP":rwx "$BIN" 2>/dev/null || true
  setfacl -d -m g:"$GROUP":rwx,m::rwx "$BIN" 2>/dev/null || true
fi

# enable password-based authentication
if [ -f /etc/ssh/sshd_config ]; then
  if grep -q '^PasswordAuthentication' /etc/ssh/sshd_config; then
    sed -i 's/^PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
  else
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config
  fi
fi

# remove configuration / process-id lifecycle files from the shared dir
find "$SHARE" -maxdepth 1 -type f \( -name '*.pid' -o -name '*.bak' \) -delete 2>/dev/null || true
exit 0
SH
chmod 0755 /app/configure.sh

# ---------------------------------------------------------------------- fixperms.sh
cat > /app/fixperms.sh <<'SH'
#!/bin/bash
# prism-anchor fixperms.sh
# Usage: fixperms.sh DIR
# Restores owner rwx / group rx / other rx on every *.sh script directly in DIR.
set -u
DIR="${1:?usage: fixperms.sh DIR}"
[ -d "$DIR" ] || exit 0
find "$DIR" -maxdepth 1 -type f -name '*.sh' -print0 2>/dev/null | while IFS= read -r -d '' f; do
  chmod 0755 "$f"
  [ "$(stat -c %U "$f")" = root ] && chown root:root "$f" || true
done
exit 0
SH
chmod 0755 /app/fixperms.sh

# ---------------------------------------------------------------------- mapper.py
cat > /app/mapper.py <<'PY'
"""normalize(): canonical map used across the PRISM shared area."""
import json
import sys


def normalize(items):
    out = []
    seen = set()
    for it in items:
        s = str(it).strip()
        if s == "":
            continue
        if s not in seen:
            seen.add(s)
            out.append(s)
    return out


if __name__ == "__main__":
    path = sys.argv[1] if len(sys.argv) > 1 else "examples.json"
    data = json.load(open(path))
    outputs = []
    match = True
    for case in data["cases"]:
        got = normalize(case["input"])
        outputs.append(got)
        if got != case["expected"]:
            match = False
    print(json.dumps(outputs))
    print("all-match" if match else "mismatch")
PY
chmod 0644 /app/mapper.py

# ------------------------------------------------------------------- configure / fix
bash /app/configure.sh /srv/prism anchorline
bash /app/fixperms.sh /srv/prism/bin

# --------------------------------------------------------------------- recovery
# The bootstrap telemetry service is provisioned asynchronously when the
# container comes up: it may take a few seconds for the process (and then its
# deleted-but-open source fd) to become visible. Poll until it is ready so we
# never bail early and always produce /app/dump.txt.
PID=""
for _ in $(seq 1 60); do
  for p in $(pgrep -x python3 2>/dev/null); do
    args=$(tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null || true)
    case "$args" in *"prism-north/telemetry.py"*) PID="$p"; break 2;; esac
  done
  [ -n "$PID" ] && break
  sleep 1
done
if [ -z "$PID" ]; then
  echo "oracle: telemetry process not found" >&2; exit 1
fi
FD=""
for _ in $(seq 1 30); do
  FD=""
  for d in /proc/$PID/fd/*; do
    t=$(readlink "$d" 2>/dev/null) || continue
    case "$t" in *deleted*) FD="${d##*/}"; break;; esac
  done
  [ -n "$FD" ] && break
  sleep 1
done
[ -n "$FD" ] || { echo "oracle: no deleted fd" >&2; exit 1; }
REC=$(cat "/proc/$PID/fd/$FD") || { echo "oracle: cannot read fd" >&2; exit 1; }
printf '%s\n' "$REC" > /tmp/recovered_telemetry.py

SECRET=$(printf '%s\n' "$REC" | sed -n 's/^SECRET = "\([^"]*\)"/\1/p' | head -1)

# ----------------------------------------------------------------------- transform
TRANSFORM=$(cd /app && python3 mapper.py /app/examples.json)
TRANSFORM_OK=$(cd /app && python3 mapper.py /app/examples.json | tail -1)

# -------------------------------------------------------------------------- suite
SUITE_LOG=/tmp/suite_run.log
python3 -m pytest -q /app/qa/suite >"$SUITE_LOG" 2>&1 || true
SUITE_TAIL=$(tail -n 30 "$SUITE_LOG")
SUITE_LINE=$(grep -E '[0-9]+ passed' "$SUITE_LOG" | tail -1)

# ------------------------------------------------------------------------ profile
python3 -m cProfile -o /tmp/pstats.out /app/prism_work.py >/dev/null 2>&1 || true
PROFILE_TOP=$(python3 - <<'PY'
import pstats
p = pstats.Stats('/tmp/pstats.out').strip_dirs()
import io
b = io.StringIO()
p.sort_stats('cumtime').print_stats(5)
lines = b.getvalue().splitlines()
# keep only the function-call tally lines after the header
body = [l for l in lines if ('spin_tally' in l) or (l.strip() and l.strip()[0].isdigit())]
print("\n".join(body[:6]))
PY
)

# ------------------------------------------------------------------ terminal tail
TERM_TAIL=$(tail -n 1 /tmp/prism-north/boot.log 2>/dev/null || true)

# ------------------------------------------------------------------- assemble dump
{
  echo "====[SERVER_RECOVERY]===="
  cat /tmp/recovered_telemetry.py
  echo "====[SECRET]===="
  echo "$SECRET"
  echo "====[TRANSFORM]===="
  printf '%s\n' "$TRANSFORM" | head -n1
  echo "====[TRANSFORM_OK]===="
  echo "$TRANSFORM_OK"
  echo "====[SUITE_TAIL]===="
  printf '%s\n' "$SUITE_LINE"
  echo "====[PROFILE_TOP]===="
  printf '%s\n' "$PROFILE_TOP"
  echo "====[TERMINAL_TAIL]===="
  echo "$TERM_TAIL"
} > /app/dump.txt

echo "PRISM-ANCHOR ORACLE COMPLETE"
exit 0