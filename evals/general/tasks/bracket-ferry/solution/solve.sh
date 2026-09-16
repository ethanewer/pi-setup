#!/bin/bash
# Oracle for bracket-ferry: fixes the `pip show` crash on distributions
# whose metadata has no Metadata-Version header, exactly as a competent
# agent would, inside the pinned checkout at /app/src.
# It NEVER reads /tests.
set -euo pipefail

SRC=/app/src
SHOW="$SRC/src/pip/_internal/commands/show.py"

# 1) Apply the fix: only build the version tuple when there IS a version.
python3 - "$SHOW" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
source = path.read_text()
old = '        metadata_version_tuple = tuple(map(int, dist.metadata_version.split(".")))'
new = (
    "        metadata_version = dist.metadata_version\n"
    "        metadata_version_tuple = (\n"
    '            tuple(map(int, metadata_version.split("."))) if metadata_version else ()\n'
    "        )"
)
assert old in source, "show.py does not match the pinned checkout; aborting"
path.write_text(source.replace(old, new))
print("patched", path)
PY

# 2) Prove the user-visible contract end to end: `pip show` on a package
#    whose dist-info METADATA has no Metadata-Version header must print the
#    package fields instead of crashing.
rm -rf /tmp/oracle-pkgs
mkdir -p /tmp/oracle-pkgs/demo_pkg-1.0.dist-info
printf 'Name: demo-pkg\nVersion: 1.0\nSummary: legacy metadata, no version\n' \
  > /tmp/oracle-pkgs/demo_pkg-1.0.dist-info/METADATA
cd "$SRC"
output=$(PYTHONPATH=src:/tmp/oracle-pkgs python3 -m pip show demo-pkg 2>&1)
grep -q "Name: demo-pkg" <<<"$output"
grep -q "Version: 1.0" <<<"$output"
! grep -q "Traceback" <<<"$output"

# 3) The project's own regression test for this bug must pass.
PYTHONPATH=src python3 -m pytest -q -o addopts= -p no:cacheprovider \
  /opt/golden/test_command_show.py

# 4) The project's own existing unit slice must stay green.
PYTHONPATH=src python3 -m pytest -q -p no:cacheprovider \
  tests/unit/test_commands.py tests/unit/metadata/test_metadata.py

echo "bracket-ferry oracle done"