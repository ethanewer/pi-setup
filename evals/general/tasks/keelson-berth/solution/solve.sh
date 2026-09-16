#!/bin/bash
# Oracle for keelson-berth.  Installs the reference Maven project (the real
# solver: JDK com.sun.net.httpserver service, hand-rolled JSON codec,
# constructor-injected repository over SQLite via JDBC, JUnit 5 suite) at
# /app/service, writes the launcher exactly as the agent must, then PROVES
# the stack by building offline with Maven, launching against the visible
# fixture and exercising the contract over real HTTP.  Never reads /tests.
set -eu

rm -rf /app/service
cp -r /solution/service /app/service

cat > /app/run_server.sh <<'RUNEOF'
#!/bin/bash
# Launcher for the keelson-berth catalogue service.
# Usage: bash /app/run_server.sh DB_PATH PORT
# Builds the service offline (mvn verify runs the JUnit suite), copies the
# runtime dependencies next to the project jar, launches the service in the
# background with the SQLite JDBC driver on the classpath, records the PID
# in /app/server.pid and returns immediately.  Server output goes to
# /app/server.out.log.  Readiness: GET /healthz on PORT.
set -u
DB="${1:?usage: run_server.sh DB_PATH PORT}"
PORT="${2:?usage: run_server.sh DB_PATH PORT}"
cd /app/service || { echo "no /app/service" >&2; exit 1; }

mvn -q -B -o -Dmaven.repo.local=/opt/m2repo verify \
  || { echo "mvn verify failed" >&2; exit 1; }
mvn -q -B -o -Dmaven.repo.local=/opt/m2repo dependency:copy-dependencies \
  -DoutputDirectory=target/dependency \
  || { echo "mvn dependency:copy-dependencies failed" >&2; exit 1; }

JAR=target/catalog-service.jar
[ -f "$JAR" ] || { echo "no project jar at $JAR" >&2; exit 1; }

if [ -f /app/server.pid ]; then
  kill "$(cat /app/server.pid)" 2>/dev/null || true
  rm -f /app/server.pid
fi

nohup java -cp "$JAR:target/dependency/*" catalog.Main "$DB" "$PORT" \
  > /app/server.out.log 2>&1 &
echo $! > /app/server.pid
RUNEOF
chmod +x /app/run_server.sh

# ---- prove the stack: offline build + real launch against the visible
# fixture + real HTTP contract calls -------------------------------------
cd /app/service
mvn -q -B -o -Dmaven.repo.local=/opt/m2repo verify
mvn -q -B -o -Dmaven.repo.local=/opt/m2repo dependency:copy-dependencies \
  -DoutputDirectory=target/dependency

rm -f /app/server.pid /app/server.out.log
bash /app/run_server.sh /app/db/items.sqlite 18080

OK=0
for i in $(seq 1 60); do
  CODE=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/healthz 2>/dev/null || true)
  if [ "$CODE" = "200" ]; then OK=1; break; fi
  sleep 0.25
done
if [ "$OK" != "1" ]; then
  echo "oracle smoke: server never became ready" >&2
  cat /app/server.out.log >&2 || true
  exit 1
fi

C=$(curl -s http://127.0.0.1:18080/api/v1/items)
echo "$C" | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["count"] == 10, d; assert len(d["items"]) == 10'
[ "$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:18080/api/v1/items/ml-001)" = "200" ] \
  || { echo "oracle smoke: GET single failed" >&2; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' "http://127.0.0.1:18080/api/v1/items?category=audio")" = "200" ] \
  || { echo "oracle smoke: category filter failed" >&2; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' -X POST -d '{"sku":"sm-90","title":"Smoke row","price":1.5,"quantity":1,"category":"audio"}' http://127.0.0.1:18080/api/v1/items)" = "201" ] \
  || { echo "oracle smoke: POST failed" >&2; exit 1; }
[ "$(curl -s -o /dev/null -w '%{http_code}' -X DELETE http://127.0.0.1:18080/api/v1/items/sm-90)" = "200" ] \
  || { echo "oracle smoke: DELETE failed" >&2; exit 1; }

kill "$(cat /app/server.pid)" 2>/dev/null || true
rm -f /app/server.pid
echo "oracle built, tested and launched the catalogue service"