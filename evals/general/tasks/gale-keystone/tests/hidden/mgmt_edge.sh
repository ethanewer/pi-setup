#!/usr/bin/env bash
# Hidden case 3: the management control path is genuinely picky — wrong media
# type or wrong admin header must be refused (400 + message), while the
# correct crafted request is answered with credentials.
set -u
BASE="http://127.0.0.1:8129"

code=$(curl -s -o /tmp/mg1.txt -w '%{http_code}' "$BASE/mgmt/token" \
       -H "Content-Type: application/json" -H "X-Admin: keys-inside-A" -d '{"scope":"ops"}')
[ "$code" = "400" ] || { echo "hidden-mgmt: wrong content type accepted ($code)"; exit 1; }
grep -q '"message"' /tmp/mg1.txt || { echo "hidden-mgmt: refusal body has no message"; exit 1; }

code=$(curl -s -o /tmp/mg2.txt -w '%{http_code}' "$BASE/mgmt/token" \
       -H "Content-Type: application/x-credentials-grant" -H "X-Admin: bogus" -d '{"scope":"ops"}')
[ "$code" = "400" ] || { echo "hidden-mgmt: wrong admin header accepted ($code)"; exit 1; }

bash /app/mgmt-request.sh >/tmp/mg3.out 2>&1 || { echo "hidden-mgmt: mgmt-request.sh failed"; exit 1; }
grep -q '^200$' /tmp/mg3.out || { echo "hidden-mgmt: crafted request not answered with 200"; exit 1; }
grep -q 'token.entry.glacier.a1b2c3' /tmp/mg3.out || { echo "hidden-mgmt: no credential in reply"; exit 1; }

echo "hidden-mgmt: picky endpoint refuses wrong inputs and answers the crafted request"
exit 0