#!/bin/sh
set -eu
python - <<'PY'
from pathlib import Path

path = Path("/app/httpx/_models.py")
text = path.read_text()
old = "        self.url = URL(url)\n        if params is not None:\n            self.url = self.url.copy_merge_params(params=params)"
new = "        self.url = URL(url) if params is None else URL(url, params=params)"
if old not in text:
    raise SystemExit("request URL construction pattern not found")
path.write_text(text.replace(old, new, 1))
PY
