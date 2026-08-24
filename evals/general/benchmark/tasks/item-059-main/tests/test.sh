#!/bin/bash
# Verifier for item-059-main.
# reward = 1  if all artifacts correct AND the pypiserver is still reachable
#          0.5 if all artifacts correct but server unreachable at verify time
#          0   otherwise
mkdir -p /logs/verifier
reward=0

python3 - <<'EOF'
import json, os, re, sys, zipfile, glob

fail = []
def check(name, cond):
    if not cond: fail.append(name)

# 1) wheel exists with correct metadata
wheels = glob.glob("/app/source/dist/demo-*.whl")
check("wheel_exists", len(wheels) == 1 and os.path.exists(wheels[0]))
if wheels:
    whl = wheels[0]
    try:
        z = zipfile.ZipFile(whl)
        metas = [n for n in z.namelist() if n.endswith(".dist-info/METADATA")]
        check("wheel_metadata_entry", len(metas) == 1)
        if metas:
            meta = z.read(metas[0]).decode("utf-8", "replace")
            check("wheel_metadata_name", re.search(r"^Name:\s*demo\s*$", meta, re.M) is not None)
            check("wheel_metadata_version", re.search(r"^Version:\s*1\.0\.0\s*$", meta, re.M) is not None)
            check("wheel_metadata_python", re.search(r"^Requires-Python:\s*(>=)?3\.8", meta, re.M) is not None)
        # built from source dir?
        check("wheel_in_dist_dir", "demo-1.0.0" in os.path.basename(whl))
    except Exception as e:
        fail.append("wheel_unreadable:%s" % e)

# 2) served copy exists in PEP-503 layout
check("served_copy", os.path.exists("/app/store/demo/demo-1.0.0-py3-none-any.whl"))

# 3) clean env install works
check("venv_python", os.path.exists("/app/clean/bin/python3") or os.path.exists("/app/clean/bin/python"))
import subprocess, textwrap
venv_py = "/app/clean/bin/python3"
if os.path.exists(venv_py):
    r = subprocess.run([venv_py, "-c", "import demo; print(demo.__version__, demo.greet('agent'))"],
                       capture_output=True, text=True)
    check("venv_install", r.returncode == 0 and r.stdout.strip() == "1.0.0 Hello, agent!")
else:
    fail.append("venv_python")

# 4) results.json present + internally consistent
rp = "/app/results.json"
if os.path.exists(rp):
    try:
        res = json.load(open(rp))
        check("results_version", res.get("wheel_metadata_version") == "1.0.0")
        check("results_install_version", res.get("clean_install_version") == "1.0.0")
        check("results_listed", res.get("project_page_listed_versions") == ["1.0.0"])
        check("results_status", res.get("project_page_status") == 200)
    except Exception as e:
        fail.append("results_unparsable:%s" % e)
else:
    fail.append("results_missing")

sys.exit(0 if not fail else 1)
EOF
BASE_OK=$?

if [ $BASE_OK -eq 0 ]; then
  # server still reachable?
  if curl -fsS --max-time 5 http://127.0.0.1:8080/simple/ >/dev/null 2>&1 \
     && curl -fsS --max-time 5 http://127.0.0.1:8080/simple/demo/ | grep -q "1.0.0"; then
    reward=1
  else
    reward=0.5
  fi
fi

echo "$reward" > /logs/verifier/reward.txt
exit 0