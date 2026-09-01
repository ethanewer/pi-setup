#!/usr/bin/env bash
set -eu
ME=vine-helix

# --------------------------------------------------------------------------
# Author the primary deliverable: /app/configure.sh
# --------------------------------------------------------------------------
cat > /app/configure.sh <<'CFG'
#!/usr/bin/env bash
#
# vine-helix / petal-node configure.sh
#
# Repairs and provisions the local Petal analysis node so that every repaired
# subsystem can be verified on a (re-)run. Idempotent and safe to run twice.
set -euo pipefail

PASS='PetalGrove-74Rook'

# 1) password-based login for the petal account --------------------------
echo "juna:$PASS" | chpasswd
usermod -s /bin/bash -U juna
mkdir -p /etc/ssh/sshd_config.d
printf 'PasswordAuthentication yes\nPermitRootLogin no\n' > /etc/ssh/sshd_config.d/petal.conf

# 2) shared group area: outsiders denied, group scripts usable ------------
chgrp -R petal /app/shared
chmod 750 /app/shared
chmod 2775 /app/shared/scripts
find /app/shared -type f -name '*.sh' -exec chmod 0755 {} +

# 3) cleanup worker: honor in-flight cleanup on cancellation ----------------
cat > /app/cleanup/sweep.py <<'PY'
#!/usr/bin/env python3
import os, signal, sys, time
LOG = "/app/cleanup/sweep.log"

def log(line):
    with open(LOG, "a") as fh:
        fh.write(line + "\n")

STOP = False

def stop(signum, frame):
    global STOP
    STOP = True  # set-and-return: never exit here, cleanup must run
    # (removed the buggy sys.exit(0))

def run_bundle(k):
    deadline = time.monotonic() + 0.35
    while time.monotonic() < deadline:
        _ = k * 7

def main():
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    k = 0
    while not STOP:
        run_bundle(k)
        k += 1
        if k > 400:
            break
    log("cleanup-complete bundle=%d" % k)

if __name__ == "__main__":
    main()
PY
chmod 644 /app/cleanup/sweep.py

# 4) profile the python workloads with cProfile and record the band ----------
mkdir -p /app/prof
python3 -m cProfile -o /app/prof/digest_slow.stats /app/jobs/digest_slow.py 300
python3 -m cProfile -o /app/prof/digest_fast.stats /app/jobs/digest_fast.py 300
python3 -m cProfile -o /app/prof/refine_slow.stats /app/jobs/refine_slow.py 300
python3 -m cProfile -o /app/prof/refine_fast.stats /app/jobs/refine_fast.py 300
python3 - <<'PY'
import pstats
pairs = [
    ("digest", "digest_slow", "digest_fast"),
    ("refine", "refine_slow", "refine_fast"),
]
lines = []
for name, sl, fa in pairs:
    s = pstats.Stats("/app/prof/%s.stats" % sl).total_tt
    f = pstats.Stats("/app/prof/%s.stats" % fa).total_tt
    ok = "yes" if (f < 1.0 and f < s) else "no"
    lines.append("%s: slow=%.2f fast=%.2f faster_ok=%s" % (name, s, f, ok))
with open("/app/prof/band.txt", "w") as fh:
    fh.write("\n".join(lines) + "\n")
print("band recorded")
PY

# 5) node trial checker: author the solution, run the bundled runner ---------
cat > /app/check/solution.json <<'J'
{"alpha": 7, "beta": 11, "gamma": 5}
J
node /app/check/runner.mjs

# 6) purge lifecycle files -------------------------------------------------
rm -f /app/registry/registry.conf /app/registry/gw.pid

# 7) confirm in-flight cleanup runs on cancellation ------------------------
bash /app/cleanup/run_tester.sh

# 8) capture the terminal ending banner verbatim ---------------------------
bash /app/finish.sh > /app/dump.txt

echo "configure.sh: petal node provisioned"
CFG
chmod +x /app/configure.sh

# --------------------------------------------------------------------------
# Author the second deliverable: /app/fixperms.sh
# --------------------------------------------------------------------------
cat > /app/fixperms.sh <<'FPX'
#!/usr/bin/env bash
#
# usage: fixperms.sh <target-dir>
#
# Restores execute + read permission bits on every shell script (and any file
# that already carried an execute bit) under <target-dir>, so members of the
# owning group can run them. Non-script files are left untouched. Missing
# directories and empty trees are tolerated (exit 0, no-op).
set -u
dir="${1:-}"
if [ -z "$dir" ] || [ ! -d "$dir" ]; then
  echo "fixperms: nothing to fix"
  exit 0
fi
find "$dir" -type f \( -name '*.sh' -o -perm /0111 \) -exec chmod 0755 {} \;
echo "fixperms: ok"
exit 0
FPX
chmod +x /app/fixperms.sh

# --------------------------------------------------------------------------
# Run the real work so a pristine container yields all deliverables.
# --------------------------------------------------------------------------
bash /app/configure.sh
echo "$ME oracle: configure.sh ran"

bash /app/fixperms.sh /app/shared && echo "fixperms ok"
echo "$ME oracle: complete"
ls -l /app/configure.sh /app/fixperms.sh /app/dump.txt