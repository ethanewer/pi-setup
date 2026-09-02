#!/bin/bash
# Real oracle for opal-notch: write the setup.sh deliverable, then RUN it on
# the visible policy to produce /app/shell_report.json. Never reads /tests.
set -eu

SETUP="/app/setup.sh"
REPORT="/app/shell_report.json"

# ---- 1. Write the idempotent provisioning script (this IS the deliverable).
cat > "$SETUP" <<'SH'
#!/bin/bash
# Applies /app/shell_policy.json to the system account database and records
# the resulting login shells in /app/shell_report.json. Idempotent.
set -eu
python3 - <<'PY'
import json
import subprocess

POLICY = "/app/shell_policy.json"
REPORT = "/app/shell_report.json"


def current_shell(user):
    out = subprocess.run(["getent", "passwd", user],
                         capture_output=True, text=True)
    if out.returncode != 0 or not out.stdout.strip():
        return None
    return out.stdout.rstrip("\n").split(":")[-1]


with open(POLICY, "r", encoding="utf-8") as fh:
    policy = json.load(fh)
accounts = policy.get("accounts", {})

for user, shell in accounts.items():
    if current_shell(user) != shell:
        subprocess.run(["usermod", "-s", shell, user], check=True)

report = {user: current_shell(user) for user in accounts}
with open(REPORT, "w", encoding="utf-8") as fh:
    json.dump(report, fh, indent=2, sort_keys=True)
    fh.write("\n")
PY
SH
chmod +x "$SETUP"

# ---- 2. Run the produced script on the visible policy to generate the report.
bash "$SETUP"

echo "solve.sh done -> $SETUP and $REPORT"
ls -l "$SETUP" "$REPORT"