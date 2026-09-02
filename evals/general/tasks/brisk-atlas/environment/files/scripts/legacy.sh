#!/usr/bin/env bash
# Batched table-migration helper (MIT-era tool).
echo "brisk: running legacy migration batch"
touch /run/brisk-legacy-ran 2>/dev/null || true