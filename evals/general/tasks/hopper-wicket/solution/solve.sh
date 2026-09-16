#!/bin/bash
# Oracle for hopper-wicket. Installs the reference release tool into /app and
# runs it once against the visible fixture repository to prove the pipeline
# works end to end. The tool is then graded by the verifier against fresh
# hidden repositories; it never reads /tests.
set -eu

cp /solution/release.py /app/release.py
chmod +x /app/release.py

python3 /app/release.py /app/project /app/releases

echo "oracle produced /app/release.py and released /app/project"