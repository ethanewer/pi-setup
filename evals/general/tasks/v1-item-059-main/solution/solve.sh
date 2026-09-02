#!/bin/bash
# Oracle solution for item-059-main.
set -e

cd /app/source
python3 -m build --wheel

# Validate wheel metadata in isolation.
WHL=/app/source/dist/demo-1.0.0-py3-none-any.whl
python3 - "$WHL" <<'EOF'
import sys, zipfile
whl = sys.argv[1]
z = zipfile.ZipFile(whl)
meta = z.read("demo-1.0.0.dist-info/METADATA").decode()
assert "Name: demo" in meta
assert "Version: 1.0.0" in meta
assert "Requires-Python: >=3.8" in meta
print("wheel metadata OK")
EOF

# Serve from a PEP-503 layout.
mkdir -p /app/store/demo
cp "$WHL" /app/store/demo/
python3 -m pypiserver run -p 8080 /app/store > /app/pypi.log 2>&1 &

for i in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8080/simple/ >/dev/null 2>&1; then break; fi
  sleep 1
done

STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/simple/demo/)
PAGE=$(curl -fsS http://127.0.0.1:8080/simple/demo/)

# Clean-environment install from the running index.
python3 -m venv /app/clean
/app/clean/bin/pip install --quiet --index-url http://127.0.0.1:8080/simple/ \
  --trusted-host 127.0.0.1 demo

VERSION=$(/app/clean/bin/python3 -c "import demo; print(demo.__version__)")
GREET=$(/app/clean/bin/python3 -c "import demo; print(demo.greet('agent'))")
test "$VERSION" = "1.0.0"
test "$GREET" = "Hello, agent!"

python3 - "$STATUS" "$VERSION" "$GREET" <<'EOF'
import json, sys
status, ver, greet = sys.argv[1], sys.argv[2], sys.argv[3]
res = {
  "wheel_path": "/app/source/dist/demo-1.0.0-py3-none-any.whl",
  "wheel_metadata_version": "1.0.0",
  "index_base_status": 200,
  "project_page_status": int(status),
  "project_page_listed_versions": ["1.0.0"],
  "clean_install_version": ver,
  "clean_install_greeting": greet,
}
open("/app/results.json", "w").write(json.dumps(res, indent=2))
EOF

echo "done"