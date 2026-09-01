#!/bin/bash
# fern-hearth verifier. Runs the three deliverable checkers and writes the reward.
set -u

mkdir -p /logs/verifier
echo 0 > /logs/verifier/reward.txt

fail() {
  echo "FAIL: $*" >&2
  echo 0 > /logs/verifier/reward.txt
  exit 1
}

# Required deliverable artifacts.
[ -f /app/repo.git/hooks/post-receive ] || fail "missing /app/repo.git/hooks/post-receive"
[ -x /app/repo.git/hooks/post-receive ] || fail "post-receive hook is not executable"
[ -d /app/deployed ]                   || fail "missing /app/deployed"
[ -f /app/normalize_url.py ]           || fail "missing /app/normalize_url.py"
[ -f /app/urls.tsv ]                   || fail "missing /app/urls.tsv"
[ -f /app/paper_links.json ]           || fail "missing /app/paper_links.json"

# Each checker exercises a deliverable (the git pushes actually run the hook).
python3 /tests/verify_git.py    || fail "git-deploy checks"
python3 /tests/verify_urls.py   || fail "url-normalize checks"
python3 /tests/verify_papers.py || fail "paper-links checks"

echo 1 > /logs/verifier/reward.txt
echo "VERIFIER-OK"