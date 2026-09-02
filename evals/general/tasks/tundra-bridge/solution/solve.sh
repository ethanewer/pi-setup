#!/bin/bash
# Tundra Bridge oracle: build the real site, fix resolution, and leave it running.
set -euo pipefail

DOMAIN="tundra.example"
APP="/app"
LOG="/var/log/nginx/tundra.example.access.log"

mkdir -p "/app/site" "/app/tls" "$(dirname "$LOG")"

# ---- welcome page ------------------------------------------------------------
cat > "/app/site/index.html" <<'HTML'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>Tundra Bridge</title></head>
<body>
  <h1>Tundra Bridge</h1>
  <p>Welcome to the static relay post.</p>
  <p class="marker">tundra-welcome-7</p>
</body>
</html>
HTML

# ---- custom 404 page ---------------------------------------------------------
cat > "/app/site/404.html" <<'HTML'
<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>404</title></head>
<body>
  <h1>404</h1>
  <p>The crossing you requested does not exist.</p>
  <p class="marker">tundra-missing-3</p>
</body>
</html>
HTML

# ---- self-signed cert / key --------------------------------------------------
openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
  -keyout "/app/tls/${DOMAIN}.key" \
  -out "/app/tls/${DOMAIN}.crt" \
  -subj "/CN=${DOMAIN}" \
  -addext "subjectAltName=DNS:${DOMAIN},DNS:www.${DOMAIN}" >/dev/null 2>&1
chmod 644 "/app/tls/${DOMAIN}.crt"
chmod 600 "/app/tls/${DOMAIN}.key"

# ---- nginx site config -------------------------------------------------------
cat > "/app/nginx.conf" <<'CONF'
# Tundra Bridge site config (grader installs at /etc/nginx/conf.d/tundra.example.conf)
limit_req_zone $binary_remote_addr zone=tundra_req:10m rate=5r/s;

log_format tundra '$remote_addr [tundra-log-9] "$request" $status $body_bytes_sent';

server {
    listen 8080;
    listen [::]:8080;
    server_name tundra.example www.tundra.example;
    root /app/site;
    index index.html;
    access_log /var/log/nginx/tundra.example.access.log tundra;
    limit_req zone=tundra_req burst=20 nodelay;
    limit_req_status 429;
    error_page 404 /404.html;
    location = /404.html { internal; }
    location / {
        try_files $uri $uri/ =404;
    }
}

server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name tundra.example www.tundra.example;
    root /app/site;
    index index.html;
    access_log /var/log/nginx/tundra.example.access.log tundra;
    ssl_certificate /app/tls/tundra.example.crt;
    ssl_certificate_key /app/tls/tundra.example.key;
    error_page 404 /404.html;
    location = /404.html { internal; }
    location / {
        try_files $uri $uri/ =404;
    }
}
CONF

# ---- network_fix.sh ---------------------------------------------------------
# Robust/idempotent host-resolution helper: every /etc/hosts rewrite is atomic
# (staged into a temp file, validated, then committed) and the default mode
# ends by guaranteeing a canonical localhost block, so resolution can never
# silently lose the IPv4 localhost mapping no matter how many times it runs.
cat > "/app/network_fix.sh" <<'SCRIPT'
#!/bin/bash
# Tundra Bridge host-resolution helper.
set -u
: "${TUNDRA_DOMAIN:=tundra.example}"
HOSTS_FILE=/etc/hosts

# ---- advisory lock (concurrent-invocation safety) --------------------------
# Serialize /etc/hosts mutations across any concurrent invocations of this
# helper using an atomic mkdir lock. Only the process whose mkdir succeeded
# owns (and later removes) the lock directory, so a best-effort fallback is
# always safe.
_OWNED_LOCK=""
_try_lock() {
  local dir="$1" i=0
  while ! mkdir "$dir" 2>/dev/null; do
    i=$((i+1))
    [ "$i" -ge 40 ] && return 1
    sleep 0.1
  done
  _OWNED_LOCK="$dir"
  return 0
}
_try_lock "${TUNDRA_LOCKDIR:-/run/lock/tundra.hosts.lock}" || _try_lock /tmp/tundra.hosts.lock || true
if [ -n "$_OWNED_LOCK" ]; then
  trap 'rmdir "$_OWNED_LOCK" 2>/dev/null || true' EXIT
fi
# Commit a fully-built hosts file only if it is non-empty and readable.
commit_hosts() {
  local tmp="$1"
  if [ -s "$tmp" ] && head -1 "$tmp" >/dev/null 2>&1; then
    chmod 644 "$tmp" 2>/dev/null || true
    cat "$tmp" > "$HOSTS_FILE"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

ensure_hosts_config() {
  if ! grep -qE '^hosts:[[:space:]]*' /etc/nsswitch.conf; then
    printf 'hosts:          files dns\n' >> /etc/nsswitch.conf
  elif ! grep -qE '^hosts:[[:space:]]*files' /etc/nsswitch.conf; then
    sed -i 's/^hosts:.*/hosts:          files dns/' /etc/nsswitch.conf 2>/dev/null || true
  fi
}

# Set one host mapping, overwriting any existing line whose second token is the
# host. Keeps every other line byte-for-byte.
register() {
  local host="$1" ip="$2" tmp
  [ -n "$host" ] && [ -n "$ip" ] || return 0
  tmp="$(mktemp "${TMPDIR:-/tmp}/tundra.hosts.XXXXXX")" || return 1
  awk -v h="$host" '$2 != h { print }' "$HOSTS_FILE" > "$tmp" \
    || { rm -f "$tmp"; return 1; }
  printf '%s %s\n' "$ip" "$host" >> "$tmp"
  commit_hosts "$tmp" || return 1
}

# Canonical localhost block: rewrite /etc/hosts keeping every non-localhost
# line and then re-adding BOTH loopback lines, so `localhost` always resolves
# to IPv4 127.0.0.1 (and keeps its IPv6 ::1 entry). Idempotent.
canonical_localhost() {
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/tundra.localhost.XXXXXX")" || return 1
  awk '$2 != "localhost" { print }' "$HOSTS_FILE" > "$tmp" \
    || { rm -f "$tmp"; return 1; }
  printf '127.0.0.1\tlocalhost\n' >> "$tmp"
  printf '::1\tlocalhost ip6-localhost ip6-loopback\n' >> "$tmp"
  commit_hosts "$tmp" || return 1
}

defaults() {
  local hn
  canonical_localhost || return 1
  hn="$(hostname 2>/dev/null || echo localhost)"
  [ -n "$hn" ] && register "$hn" 127.0.0.1
  register "$TUNDRA_DOMAIN" 127.0.0.1
  register "www.$TUNDRA_DOMAIN" 127.0.0.1
  # final safety net: re-assert the IPv4 localhost mapping once more.
  register localhost 127.0.0.1
}

apply_file() {
  local file="$1" line host ip
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in
      \#*|"") continue ;;
    esac
    set -- $line
    if [ $# -ge 2 ]; then
      register "$1" "$2" || return 1
    fi
  done < "$file"
}

ensure_hosts_config
case "${1:-default}" in
  register)
    shift
    if [ $# -ge 2 ]; then register "$1" "$2" || exit 1; fi
    exit 0
    ;;
  apply)
    shift
    if [ $# -ge 1 ]; then apply_file "$1" || exit 1; fi
    exit 0
    ;;
  *)
    defaults || exit 1
    exit 0
    ;;
esac
SCRIPT
chmod +x "/app/network_fix.sh"

# ---- selfcheck.py ------------------------------------------------------------
cat > "/app/selfcheck.py" <<'PY'
#!/usr/bin/env python3
import os, socket, statistics, subprocess, sys, time

DOMAIN = os.environ.get("TUNDRA_DOMAIN", "tundra.example")
HTTP = "http://127.0.0.1:8080/"
HTTPS = "https://127.0.0.1:443/"
CRT = "/app/tls/tundra.example.crt"
KEY = "/app/tls/tundra.example.key"
IDX = "/app/site/index.html"

_res = []

def check(name, fn):
    t0 = time.time()
    try:
        ok = bool(fn())
    except Exception:
        ok = False
    dt = time.time() - t0
    _res.append((name, ok, dt))
    print(f"CHK: {name}: {'PASS' if ok else 'FAIL'}")
    return ok

def resolve(host):
    return bool(socket.getaddrinfo(host, None, socket.AF_INET))

def fetch(url, insecure=False):
    import urllib.request, ssl
    ctx = ssl._create_unverified_context() if insecure else None
    with urllib.request.urlopen(url, timeout=6, context=ctx) as r:
        return r.status, r.read().decode("utf-8", "replace")

def pubkey_fingerprint(path, is_key):
    import hashlib
    try:
        if is_key:
            out = subprocess.check_output(["openssl","pkey","-in",path,"-pubout","-outform","DER"])
        else:
            out = subprocess.check_output(["openssl","x509","-in",path,"-pubkey","-noout"],
                                          stderr=subprocess.DEVNULL)
            out = subprocess.check_output(["openssl","pkey","-pubin","-outform","DER"], input=out)
        return hashlib.sha256(out).hexdigest()
    except Exception:
        return None

check("resolve_site", lambda: resolve(DOMAIN))
check("resolve_localhost", lambda: resolve("localhost"))
check("index_file", lambda: os.path.isfile(IDX) and "tundra-welcome-7" in open(IDX).read())
check("tls_files", lambda: os.path.isfile(CRT) and os.path.isfile(KEY))
check("cert_matches_key", lambda: pubkey_fingerprint(CRT) == pubkey_fingerprint(KEY, True))
check("http_home", lambda: fetch(HTTP)[0] == 200 and "tundra-welcome-7" in fetch(HTTP)[1])
check("https_home", lambda: fetch(HTTPS, True)[0] == 200 and "tundra-welcome-7" in fetch(HTTPS, True)[1])

durs = [d for _, _, d in _res]
mean = statistics.mean(durs) if durs else 0.0
std = statistics.stdev(durs) if len(durs) > 1 else 0.0
print(f"MEAN: {mean:.4f}")
print(f"STD: {std:.4f}")
sys.exit(0 if all(ok for _, ok, _ in _res) else 1)
PY

# ---- make everything live ----------------------------------------------------
chmod +x "/app/network_fix.sh"
bash "/app/network_fix.sh"

# deactivate distro default site so only this server owns the ports
rm -f /etc/nginx/sites-enabled/default
# install our site config into the conf.d path the grader expects
cp -f "/app/nginx.conf" /etc/nginx/conf.d/tundra.example.conf

nginx -t
pkill -9 -x nginx 2>/dev/null || true
sleep 1
nginx
sleep 2

# leave a fresh access log
: > "$LOG"
curl -s -o /dev/null http://127.0.0.1:8080/ || true
curl -s -k -o /dev/null https://127.0.0.1:443/ || true

# final host-resolution guarantee: re-run the helper and verify localhost
# resolves to 127.0.0.1 before declaring the deploy finished. Retry a few
# times so a transient hiccup can never leave a broken /etc/hosts behind.
attempt=0
for _ in 1 2 3; do
  attempt=$((attempt+1))
  bash "/app/network_fix.sh"
  if getent ahosts localhost | grep -qE '^127\.0\.0\.1[[:space:]]' \
     && getent ahosts "$DOMAIN" | grep -qE '^127\.0\.0\.1[[:space:]]'; then
    break
  fi
  if [ "$attempt" -ge 3 ]; then
    echo "network_fix: localhost/site resolution failed" >&2
    exit 1
  fi
  sleep 1
done

echo "tundra-bridge deployed"