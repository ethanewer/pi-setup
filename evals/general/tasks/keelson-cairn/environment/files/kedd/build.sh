#!/usr/bin/env bash
# kedd build: clean-compile every source under src/ to build/. Idempotent.
set -euo pipefail
cd "$(dirname "$0")"
rm -rf build
mkdir -p build
javac -encoding UTF-8 -d build src/cairn/*.java
echo "kedd: built $(find build -name '*.class' | wc -l) classes"