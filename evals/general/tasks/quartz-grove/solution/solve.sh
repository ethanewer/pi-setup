#!/usr/bin/env bash
# Oracle for quartz-grove. Folds the whole deliverable set into /app by actually
# doing the work: building the resolver, retracting the incompatible `legacy`
# schematics, resolving ONE consistent lock, deriving the pip manifest, installing
# an isolated venv with the pinned versions, running the reference example, and
# recording the preserved global numpy. Never reads /tests.
set -euo pipefail

# 1) Deliverable program: the dependency resolver.
cp /solution/resolve.py /app/resolve.py
chmod +x /app/resolve.py

# 2) Edit /app/spec.json to drop the incompatible `legacy` module (it demands
#    numpy<1.22 while solver demands numpy>=1.24.4 -- a disjoint pair).
python3 - <<'PY'
import json
p = "/app/spec.json"
spec = json.load(open(p))
spec["modules"] = [m for m in spec["modules"] if m["name"] != "legacy"]
json.dump(spec, open(p, "w"), indent=2)
open(p, "a").write("\n")
print("retracted legacy module")
PY

# 3) Produce the consistent pinned set (environment.lock) by running the resolver.
python3 /app/resolve.py --spec /app/spec.json > /app/environment.lock
cat /app/environment.lock

# 4) Derive the pip manifest /app/requirements.txt from the lock.
python3 - <<'PY'
import json
lock = json.load(open("/app/environment.lock"))
lines = [f"numpy=={lock['numpy']}"]
seen = {"numpy"}
for m in lock["modules"].values():
    pkg, ver = m["package"], m["version"]
    if pkg not in seen:
        lines.append(f"{pkg}=={ver}")
        seen.add(pkg)
open("/app/requirements.txt", "w").write("\n".join(lines) + "\n")
print("requirements.txt:")
print(open("/app/requirements.txt").read())
PY

# 5) Isolated install: create a venv and install exactly the pinned set into it.
python3 -m venv /app/venv
/app/venv/bin/pip install --no-cache-dir -q -r /app/requirements.txt

# 6) Run the provided reference example under the venv -> example_check.log
/app/venv/bin/python /app/example_check.py > /app/example_check.log
echo "example_check.log:"; cat /app/example_check.log

# 7) frozen_versions.json: the preserved global numpy's exact pre-install value.
GLOBAL="$(cat /app/.global_numpy_original)"
GLOBAL_NOW="$(python3 -c 'import numpy; print(numpy.__version__)')"
if [ "$GLOBAL" != "$GLOBAL_NOW" ]; then
  echo "ERROR: global numpy changed ($GLOBAL -> $GLOBAL_NOW)" >&2
  exit 1
fi
python3 - "$GLOBAL" <<'PY'
import json, sys
v = sys.argv[1]
json.dump({"preserved": {"numpy": v}}, open("/app/frozen_versions.json", "w"), indent=2)
open("/app/frozen_versions.json", "a").write("\n")
print("frozen_versions.json:", open("/app/frozen_versions.json").read())
PY

echo "quartz-grove oracle complete"