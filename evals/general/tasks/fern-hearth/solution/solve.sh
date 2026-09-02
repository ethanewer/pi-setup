#!/bin/bash
# Oracle solver for fern-hearth. Builds every deliverable by doing the work.
set -euo pipefail

REPO=/app/repo.git
DEPLOY=/app/deployed

mkdir -p "${DEPLOY}"

# ---------------------------------------------------------------- part 1: hook
cat > /app/repo.git/hooks/post-receive <<'HOOK'
#!/bin/bash
# Deploy every pushed branch ref into /app/deployed/<branch>/ as an exact mirror.
set -euo pipefail
GITDIR="${GIT_DIR:-/app/repo.git}"
DEPLOY=/app/deployed

while read -r _old _new ref; do
  case "$ref" in
    refs/heads/*)
      branch="${ref#refs/heads/}"
      null="$(printf '0%.0s' {1..40})"
      if [ "${_new}" = "${null}" ]; then
        # branch deleted
        rm -rf "${DEPLOY}/${branch}"
        # remove now-empty ancestor dirs so nothing partial lingers
        dir="${DEPLOY}/${branch}"
        while [ "${dir}" != "${DEPLOY}" ]; do
          if [ -d "${dir}" ] && [ -z "$(ls -A "${dir}" 2>/dev/null)" ]; then
            rmdir "${dir}" 2>/dev/null || true
          fi
          dir="$(dirname "${dir}")"
        done
      else
        rm -rf "${DEPLOY}/${branch}"
        mkdir -p "${DEPLOY}/${branch}"
        git --git-dir="${GITDIR}" archive --format=tar "${_new}" \
          | tar -x -C "${DEPLOY}/${branch}"
      fi
      ;;
  esac
done
HOOK
chmod +x /app/repo.git/hooks/post-receive

# Deploy main with the same logic.
rm -rf "${DEPLOY}/main"
mkdir -p "${DEPLOY}/main"
git --git-dir="${REPO}" archive --format=tar main | tar -x -C "${DEPLOY}/main"

# ---------------------------------------------------------------- part 2: URL
cat > /app/normalize_url.py <<'PY'
#!/usr/bin/env python3
"""Canonical form C of repository URLs (see task spec)."""
import sys
from urllib.parse import urlsplit

DEFAULT_PORTS = {"http": 80, "https": 443, "ftp": 21}


def canonicalize(s):
    if "\n" in s:
        s = s.rstrip("\n")
    if s.strip() == "":
        return ""
    u = s.strip()
    if "://" not in u:
        return u
    p = urlsplit(u)
    scheme = p.scheme.lower()
    if not scheme:
        return u
    host = (p.hostname or "").lower()
    port = p.port
    if port is not None and port == DEFAULT_PORTS.get(scheme):
        port = None
    userinfo = ""
    if p.username is not None:
        userinfo = p.username
        if p.password is not None:
            userinfo += ":" + p.password
        userinfo += "@"
    netloc = userinfo + host
    if port is not None:
        netloc += ":" + str(port)
    path = p.path or ""
    if path:
        path = path.rstrip("/")
    params = [x for x in p.query.split("&") if x]
    params.sort(key=lambda x: x.split("=", 1)[0])
    q = "&".join(params)
    out = scheme + "://" + netloc + path
    if q:
        out += "?" + q
    return out


def normalize_lines(text):
    lines = text.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    return [canonicalize(ln) for ln in lines]


def main():
    sources = sys.argv[1:]
    if not sources:
        text = sys.stdin.read()
        for ln in normalize_lines(text):
            print(ln)
        return
    for src in sources:
        with open(src, encoding="utf-8") as f:
            for ln in normalize_lines(f.read()):
                print(ln)


if __name__ == "__main__":
    main()
PY

chmod +x /app/normalize_url.py

# ---------------------------------------------------------------- part 3: papers
cat > /app/resolve_papers.py <<'PY'
#!/usr/bin/env python3
"""Resolve every paper in /app/papers to its official GitHub repo and write
/app/paper_links.json (JSONL) and /app/urls.tsv."""
import os
import re
import sys

sys.path.insert(0, "/app")
from normalize_url import canonicalize  # noqa: E402

PAPERS = "/app/papers"


def unesc(s):
    return s.replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">")


def affiliation_of(html):
    m = re.search(r'<div class="affiliation">([^<]*)</div>', html)
    return unesc(m.group(1).strip()) if m else ""


def official_of(html, aff):
    if not aff:
        return ""
    for href in re.findall(r'<a class="repo" href="([^"]+)"', html):
        if "github.com/" not in href:
            continue
        owner = href.split("github.com/", 1)[1].split("/", 1)[0]
        if owner == aff:
            return href
    return ""


# Every paper listed in the index.
idx = open(os.path.join(PAPERS, "index.html"), encoding="utf-8").read()
pids = re.findall(r'data-pid="([^"]+)"', idx)

records = []
repos = []
for pid in pids:
    page = os.path.join(PAPERS, pid + ".html")
    url = ""
    if os.path.isfile(page):
        with open(page, encoding="utf-8") as f:
            html = f.read()
        hos = official_of(html, affiliation_of(html))
        if hos:
            url = canonicalize(hos)
    if url:
        repos.append(url)
    records.append({"id": pid, "url": url})

with open("/app/paper_links.json", "w", encoding="utf-8") as f:
    for rec in records:
        f.write(__import__("json").dumps(rec) + "\n")

with open("/app/urls.tsv", "w", encoding="utf-8") as f:
    for url in repos:
        f.write(url + "\n")

print("resolved %d papers, %d with repos" % (len(records), len(repos)))
PY

python3 /app/resolve_papers.py

echo "SOLVE-OK"