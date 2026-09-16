#!/bin/bash
# Oracle for thwart-quarry: installs the reference cache layer and the
# redis start script into the deliverable paths, then smoke-checks that
# the module imports and exposes the whole contract API. The verifier
# itself drives the concurrent workloads against a live redis.
set -eu

cp /solution/cache_layer.py /app/cache_layer.py
cp /solution/start_redis.sh /app/start_redis.sh
chmod +x /app/start_redis.sh

python3 - <<'PY'
import importlib.util

spec = importlib.util.spec_from_file_location("cache_layer", "/app/cache_layer.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
for name in ("open_cache", "cached_get", "spend"):
    assert callable(getattr(mod, name)), "missing contract function " + name
print("oracle: /app/cache_layer.py imports and exposes the contract API")
PY

echo "oracle produced /app/cache_layer.py and /app/start_redis.sh"