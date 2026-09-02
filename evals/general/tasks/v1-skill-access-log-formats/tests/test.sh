#!/bin/bash
mkdir -p /logs/verifier
reward=0
if [ -f /app/access.log ] && [ -f /app/answer.json ]; then
  if python3 - <<'EOF'
import json, re, sys
rows = []
for line in open('/app/access.log'):
    line = line.rstrip('\n')
    m = re.match(r'^(\S+)\s+\S+\s+\S+\s+\[[^\]]*\]\s+"(\S+)\s+(\S+)\s+(\S+)"\s+(\d+)\s+\S+$', line)
    if not m or m.group(2) not in ('GET','POST','PUT','DELETE','HEAD','OPTIONS'):
        raise SystemExit("unparseable line: %r" % (line,))
    ip = m.group(1); method = m.group(2); path = m.group(3); status = int(m.group(5))
    rows.append((ip, method, path, status))
exp_status = sum(1 for r in rows if r[3] == 200)
exp_ips = len(set(r[0] for r in rows))
exp_paths = sorted(set(r[2] for r in rows))
got = json.load(open('/app/answer.json'))
ok = (int(got.get('status_200_count')) == exp_status and
      int(got.get('distinct_ips_count')) == exp_ips and
      str(got.get('paths_sorted')) == str(exp_paths))
if not ok:
    raise SystemExit("mismatch got=%r exp_status=%d exp_ips=%d exp_paths=%r" % (got, exp_status, exp_ips, exp_paths))
sys.exit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt