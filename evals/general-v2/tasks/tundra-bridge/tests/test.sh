#!/bin/bash
# Tundra Bridge verifier (executes-deliverable).
set -u
mkdir -p /logs/verifier
PASS=1
fail() { echo "VERIFY FAIL: $1"; PASS=0; }

HTTP_PORT=8080
LOG=/var/log/nginx/tundra.example.access.log

finish() {
  if [ "$PASS" = "1" ]; then
    echo "ALL PASS -> reward 1"
    echo 1 > /logs/verifier/reward.txt
  else
    echo "SOME CHECKS FAILED -> reward 0"
    echo 0 > /logs/verifier/reward.txt
  fi
}
trap finish EXIT

# ---- 0. deliverables must exist (negative control fails here) -------------------
[ -f /app/nginx.conf ]                || fail "missing /app/nginx.conf"
[ -f /app/site/index.html ]           || fail "missing /app/site/index.html"
[ -f /app/tls/tundra.example.crt ]    || fail "missing tls cert"
[ -f /app/tls/tundra.example.key ]    || fail "missing tls key"
[ -f /app/network_fix.sh ]            || fail "missing network_fix.sh"
[ -x /app/network_fix.sh ]            || fail "network_fix.sh not executable"
[ -f /app/selfcheck.py ]              || fail "missing selfcheck.py"

# ---- 1. distro default site must be disabled by the solution ---------------------
if [ -e /etc/nginx/sites-enabled/default ] || [ -e /etc/nginx/conf.d/default.conf ]; then
  fail "distro default site still enabled"
fi

# ---- 2. install the deliverable config and syntax-check it -------------------------
mkdir -p /etc/nginx/conf.d
cp -f /app/nginx.conf /etc/nginx/conf.d/tundra.example.conf
grep -q 'tundra-welcome-7' /app/site/index.html        || fail "index marker missing"
grep -q 'tundra-missing-3' /app/site/404.html          || fail "404 marker missing"

# ---- 3. cert and key must match ------------------------------------------------------
certpub=$(openssl x509 -in /app/tls/tundra.example.crt -pubkey -noout 2>/dev/null \
          | openssl pkey -pubin -outform DER 2>/dev/null | md5sum)
keypub=$(openssl pkey -in /app/tls/tundra.example.key -pubout -outform DER 2>/dev/null | md5sum)
[ -n "$certpub" ] && [ "$certpub" = "$keypub" ] || fail "cert/key mismatch"

# ---- 4. nginx must start and serve ---------------------------------------------------
nginx -t >/dev/null 2>&1 || fail "nginx -t"
pkill -9 -x nginx 2>/dev/null || true
sleep 1
nginx || fail "nginx start"
sleep 2

curl -s -o /dev/null --max-time 5 "http://127.0.0.1:${HTTP_PORT}/" || fail "not listening on 8080"

# ---- 5. plain HTTP home (200 + body) -------------------------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${HTTP_PORT}/")
[ "$code" = "200" ] || fail "home http=$code"
curl -s --max-time 5 "http://127.0.0.1:${HTTP_PORT}/" | grep -q 'tundra-welcome-7' || fail "home body"

# ---- 6. custom 404 -------------------------------------------------------------------
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${HTTP_PORT}/nope-exist-long")
[ "$code" = "404" ] || fail "404 status=$code"
curl -s --max-time 5 "http://127.0.0.1:${HTTP_PORT}/nope-something-else" | grep -q 'tundra-missing-3' || fail "404 body"

# ---- 7. TLS on 443 ---------------------------------------------------------------------
code=$(curl -s -k -o /dev/null -w '%{http_code}' --max-time 5 "https://127.0.0.1:443/")
[ "$code" = "200" ] || fail "https status=$code"
curl -s -k --max-time 5 "https://127.0.0.1:443/" | grep -q 'tundra-welcome-7' || fail "https body"

# ---- 8. named access log captures the probe token --------------------------------------
PROBE=$(cat /tests/hidden/log_probe.txt)
[ -n "$PROBE" ] || fail "empty probe"
curl -s -o /dev/null --max-time 5 "http://127.0.0.1:${HTTP_PORT}/${PROBE}"
[ -f "/var/log/nginx/tundra.example.access.log" ] || fail "access log file missing"
grep -q 'tundra-log-9' /var/log/nginx/tundra.example.access.log    || fail "named log token missing"
grep -q "$PROBE"      /var/log/nginx/tundra.example.access.log    || fail "probe missing from log"

# ---- 9. name resolution helper -----------------------------------------------------------
bash /app/network_fix.sh || fail "network_fix default"
getent ahosts tundra.example | grep -qE '^127\.0\.0\.1[[:space:]]' || fail "site not resolvable"
getent ahosts localhost     | grep -qE '^127\.0\.0\.1[[:space:]]' || fail "localhost not resolvable"

# ---- hidden: status_checks.tsv ------------------------------------------------------------
while IFS=$'\t' read -r path want; do
  [ -n "$path" ] || continue
  got=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${HTTP_PORT}${path}")
  [ "$got" = "$want" ] || fail "status ${path}: want=$want got=$got"
done < /tests/hidden/status_checks.tsv

# ---- hidden: aliases.tsv ----------------------------------------------------------------------
if ! bash /app/network_fix.sh apply /tests/hidden/aliases.tsv; then
  fail "network_fix apply crashed"
fi
while IFS=$'\t' read -r host ip; do
  case "$host" in
    ''|\#*) continue ;;
  esac
  [ -n "$host" ] && [ -n "$ip" ] || continue
  bash /app/network_fix.sh register "$host" "$ip" || fail "register $host"
  getent ahosts "$host" | grep -qE "^$ip[[:space:]]" || fail "resolve $host -> $ip"
done < /tests/hidden/aliases.tsv

# ---- self-test format -------------------------------------------------------------
out=$(python3 /app/selfcheck.py 2>&1)
n_chk=$(printf '%s\n' "$out" | grep -cE '^CHK: (.)*: (PASS|FAIL)$')
[ "$n_chk" -ge 4 ] || fail "selfcheck CHK count=$n_chk"
printf '%s\n' "$out" | grep -qE '^CHK: .*: PASS$'                || fail "no PASS"
printf '%s\n' "$out" | grep -qE '^MEAN: [0-9]+\.[0-9]+'          || fail "MEAN"
printf '%s\n' "$out" | grep -qE '^STD: [0-9]+\.[0-9]+'           || fail "STD"

# ---- per-IP rate limiting burst -----------------------------------------------------------------
burst=0
for i in $(seq 1 60); do
  c=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://127.0.0.1:${HTTP_PORT}/x${i}")
  [ "$c" = "429" ] && burst=$((burst+1))
done
[ "$burst" -ge 15 ] || fail "rate-limit 429 got=$burst"

exit 0