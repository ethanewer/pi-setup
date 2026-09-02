#!/bin/bash
# Oracle solution for item-059-hard.
set -e

cd /app/source

# 1) Build & validate 1.0.0
python3 -m build --wheel
WHL00=/app/source/dist/demo-1.0.0-py3-none-any.whl

# 2) Bump to 1.0.1 in both places, rebuild
sed -i 's/^version = "1.0.0"/version = "1.0.1"/' pyproject.toml
sed -i 's/__version__ = "1.0.0"/__version__ = "1.0.1"/' demo/__init__.py
python3 -m build --wheel
WHL01=/app/source/dist/demo-1.0.1-py3-none-any.whl

python3 - "$WHL00" "$WHL01" <<'EOF'
import sys, zipfile
for whl, ver in ((sys.argv[1], "1.0.0"), (sys.argv[2], "1.0.1")):
    z = zipfile.ZipFile(whl)
    metas = [n for n in z.namelist() if n.endswith(".dist-info/METADATA")]
    assert len(metas) == 1
    meta = z.read(metas[0]).decode()
    assert "Name: demo" in meta
    assert "Version: %s" % ver in meta
    assert "Requires-Python: >=3.8" in meta
print("metadata OK for both")
EOF

# 3) Serve both
mkdir -p /app/store/demo
cp "$WHL00" /app/store/demo/
cp "$WHL01" /app/store/demo/
# pypiserver 2.x: console script is `pypi-server`, and the `run` subcommand is
# required with the package dir as a positional arg; -a . -P . disables auth.
python3 -m pypiserver run --port 8080 -a . -P . /app/store > /app/pypi.log 2>&1 &

for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/simple/ >/dev/null 2>&1; then break; fi
  sleep 1
done
PAGE=$(curl -fsS http://127.0.0.1:8080/simple/demo/)
STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/simple/demo/)

# 4) pinned clean installs from the index
python3 -m venv /app/clean_100
/app/clean_100/bin/pip install --quiet --index-url http://127.0.0.1:8080/simple/ \
  --trusted-host 127.0.0.1 "demo==1.0.0"
python3 -m venv /app/clean_101
/app/clean_101/bin/pip install --quiet --index-url http://127.0.0.1:8080/simple/ \
  --trusted-host 127.0.0.1 "demo==1.0.1"

# Run the import probes from a neutral cwd: /app/source/demo shadows the venv
# installs when cwd is /app/source.
V100=$(cd /tmp && /app/clean_100/bin/python3 -c "import demo; print(demo.__version__)")
V101=$(cd /tmp && /app/clean_101/bin/python3 -c "import demo; print(demo.__version__)")
test "$V100" = "1.0.0"
test "$V101" = "1.0.1"

# 5) negative: 9.9.9 must fail
if /app/clean_101/bin/pip install --index-url http://127.0.0.1:8080/simple/ \
     --trusted-host 127.0.0.1 "demo==9.9.9" >/dev/null 2>&1; then
  echo "expected failure did not happen"; exit 1
fi

python3 - "$STATUS" "$V100" "$V101" <<'EOF'
import json, sys
res = {
  "wheels_built": ["demo-1.0.0-py3-none-any.whl", "demo-1.0.1-py3-none-any.whl"],
  "index_base_status": 200,
  "project_page_status": int(sys.argv[1]),
  "project_page_listed_versions": ["1.0.0", "1.0.1"],
  "clean_100_version": sys.argv[2],
  "clean_101_version": sys.argv[3],
  "install_999_failed_as_expected": True,
}
open("/app/results.json", "w").write(json.dumps(res, indent=2))
EOF

echo "done"