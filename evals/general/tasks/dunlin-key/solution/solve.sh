#!/bin/bash
# Oracle for dunlin-key: write the packing tool, make it executable, and run
# both subcommands on the shipped tree to produce the release artifacts.
# Never reads /tests.
set -euo pipefail

cp /solution/pack_index.py /app/pack_index.py
chmod +x /app/pack_index.py

python3 /app/pack_index.py index /app/fw_tree /app/index.json
python3 /app/pack_index.py pack /app/fw_tree /app/bundle.zip

# Sanity: re-run both subcommands and require byte-identity.
python3 /app/pack_index.py index /app/fw_tree /tmp/dk_index2.json
python3 /app/pack_index.py pack /app/fw_tree /tmp/dk_bundle2.zip
cmp /app/index.json /tmp/dk_index2.json
cmp /app/bundle.zip /tmp/dk_bundle2.zip

python3 - <<'PY'
import json, zipfile
obj = json.load(open('/app/index.json'))
assert obj['format'] == 'fw-bundle-index-1' and len(obj['entries']) == 9, obj['format']
assert [e['path'] for e in obj['entries']][0] == 'Audit.log'
zf = zipfile.ZipFile('/app/bundle.zip')
assert zf.namelist()[0] == 'Audit.log' and len(zf.namelist()) == 9
assert zf.infolist()[0].date_time == (1980, 1, 1, 0, 0, 0)
print('oracle: index.json and bundle.zip deterministic, 9 members, ok')
PY

echo "solve.sh done -> /app/pack_index.py, /app/index.json, /app/bundle.zip"
ls -l /app/pack_index.py /app/index.json /app/bundle.zip
