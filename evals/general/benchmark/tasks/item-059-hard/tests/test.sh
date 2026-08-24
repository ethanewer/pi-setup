#!/bin/bash
# Verifier for item-059-hard.
# reward = 1  if all artifacts correct AND server still reachable
#          0.5 if all artifacts correct but server unreachable at verify time
#          0   otherwise
mkdir -p /logs/verifier
reward=0

python3 - <<'EOF'
import json, os, re, sys, subprocess, zipfile, glob

fail = []
def check(name, cond):
    if not cond: fail.append(name)

# 1) both wheels exist with correct metadata
for ver in ("1.0.0", "1.0.1"):
    whl = "/app/source/dist/demo-%s-py3-none-any.whl" % ver
    check("wheel_%s_exists" % ver, os.path.exists(whl))
    if not os.path.exists(whl): continue
    try:
        z = zipfile.ZipFile(whl)
        metas = [n for n in z.namelist() if n.endswith(".dist-info/METADATA")]
        check("meta_%s_entry" % ver, len(metas) == 1)
        if metas:
            meta = z.read(metas[0]).decode("utf-8", "replace")
            check("meta_%s_name" % ver, re.search(r"^Name:\s*demo\s*$", meta, re.M))
            check("meta_%s_version" % ver, re.search(r"^Version:\s*%s\s*$" % ver, meta, re.M))
            check("meta_%s_python" % ver, re.search(r"^Requires-Python:\s*(>=)?3\.8", meta, re.M))
    except Exception as e:
        fail.append("wheel_%s_unreadable:%s" % (ver, e))

# 2) both served copies
for ver in ("1.0.0", "1.0.1"):
    check("served_%s" % ver, os.path.exists("/app/store/demo/demo-%s-py3-none-any.whl" % ver))

# 3) clean envs with pinned versions
def env_version(env, expected, name):
    py = os.path.join(env, "bin", "python3")
    check("%s_py" % name, os.path.exists(py))
    if os.path.exists(py):
        r = subprocess.run([py, "-c", "import demo; print(demo.__version__)"],
                           capture_output=True, text=True)
        check("%s_version" % name, r.returncode == 0 and r.stdout.strip() == expected)
    else:
        fail.append(name + "_env_missing")

env_version("/app/clean_100", "1.0.0", "clean100")
env_version("/app/clean_101", "1.0.1", "clean101")

# 4) results.json consistent
rp = "/app/results.json"
if os.path.exists(rp):
    try:
        res = json.load(open(rp))
        check("res_listed", sorted(res.get("project_page_listed_versions", [])) == ["1.0.0", "1.0.1"])
        check("res_100", res.get("clean_100_version") == "1.0.0")
        check("res_101", res.get("clean_101_version") == "1.0.1")
        check("res_999", res.get("install_999_failed_as_expected") is True)
    except Exception as e:
        fail.append("results_unparsable:%s" % e)
else:
    fail.append("results_missing")

sys.exit(0 if not fail else 1)
EOF
BASE_OK=$?

if [ $BASE_OK -eq 0 ]; then
  PAGE=$(curl -fsS --max-time 5 http://127.0.0.1:8080/simple/demo/ 2>/dev/null)
  if [ -n "$PAGE" ] && echo "$PAGE" | grep -q "demo-1.0.0" && echo "$PAGE" | grep -q "demo-1.0.1"; then
    reward=1
  else
    reward=0.5
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0