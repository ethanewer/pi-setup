#!/bin/bash
# Guarantee a reward on every exit path. Without this a verifier that
# raises while inspecting the agent's deliverable writes nothing at all,
# which yields a record that cannot be scored.
trap '[ -f /logs/verifier/reward.txt ] || { echo "VERIFIER EXITED WITHOUT WRITING A REWARD; scoring 0" >&2; mkdir -p /logs/verifier; echo 0 > /logs/verifier/reward.txt; }' EXIT

mkdir -p /logs/verifier
reward=0
if [ -f /app/answer.json ]; then
  if python3 - <<'EOF'
import json, re
exp={
 "package_manager":"apk",
 "c_library":"musl",
 "repositories_file":"/etc/apk/repositories",
 "init_system":"openrc",
}
def norm(s):
    return re.sub(r'[^a-z0-9/_\.-]','',str(s).strip().lower())
got=json.load(open('/app/answer.json'))
for k,v in exp.items():
    if norm(got.get(k,'')) != norm(v):
        raise SystemExit("bad %s: got %r want %r" % (k,got.get(k),v))
print("PASS"); raise SystemExit(0)
EOF
  then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt