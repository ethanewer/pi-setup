#!/bin/bash
# fix-fetch.sh -- diagnose + repair the broken egress fetch, then save the page.
#
# Root cause: the outbound tool honours an override file /app/override/proxy.txt
# whose value currently points at a broken egress proxy (127.0.0.1:8051) that
# answers every request with a 502 proxy error page. Repair = neutralise that
# override and re-run the fetch so it hits the real endpoint.
set -euo pipefail

# 1) Neutralise the broken override.
rm -f /app/override/proxy.txt

# 2) Re-fetch the page through the now-clean path.
mkdir -p /app/fetched
python3 /app/puller.py http://127.0.0.1:9000/page -o /app/fetched/page.html

echo "fetch repaired; page saved to /app/fetched/page.html"