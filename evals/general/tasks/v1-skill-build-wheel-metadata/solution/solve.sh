#!/usr/bin/env bash
set -euo pipefail

cat > /app/melonpkg/pyproject.toml <<'PY_END'
[build-system]
requires = ["setuptools>=61"]
build-backend = "setuptools.build_meta"

[project]
name = "melonpkg"
version = "1.4.0"
description = "Melon math helpers"
requires-python = ">=3.8"

[tool.setuptools]
packages = ["pkg"]
PY_END

mkdir -p /app/dist
cd /app/melonpkg
pip wheel . --no-build-isolation --no-deps -w /app/dist

WHL=$(ls /app/dist/*.whl | head -1)
unzip -p "$WHL" '*/METADATA' > /app/meta_report.txt

grep -q '^Name: melonpkg' /app/meta_report.txt
grep -q '^Version: 1.4.0' /app/meta_report.txt