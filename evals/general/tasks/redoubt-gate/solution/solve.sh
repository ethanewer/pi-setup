#!/bin/bash
# Oracle for redoubt-gate.
#
# Installs the reference FIXED project at /app/service (exclusion of
# com.example:formatter from lib-y + a maven-enforcer bannedDependencies
# rule on com.example:formatter:2.0.0 bound to the validate phase), then
# proves the whole stack fully offline, exactly as the verifier will:
#   1. `mvn -B -o verify` is green,
#   2. `mvn -B -o dependency:tree` shows exactly one version of
#      com.example:formatter -- 1.0.0,
#   3. reintroducing the conflict makes `mvn -B -o validate` fail
#      (the enforcer rule fires).
# The oracle never reads /tests.
set -eu

rm -rf /app/service
cp -r /solution/service /app/service
cd /app/service

M=(-o -Dmaven.repo.local=/opt/m2repo)

# ---- 1. the shipped suite (GreetingTest) must compile and pass, offline
mvn -q -B "${M[@]}" verify
echo "oracle: mvn -B -o verify green"

# ---- 2. exactly one formatter version on the graph: 1.0.0
mvn -B "${M[@]}" dependency:tree > /tmp/oracle-tree.txt 2>&1
vers=$(grep -o 'com.example:formatter:[0-9][^ :]*' /tmp/oracle-tree.txt \
        | sed 's/.*://' | sort -u | tr '\n' ' ')
if [ "$vers" != "1.0.0 " ]; then
  echo "oracle: dependency:tree formatter versions are '[$vers]', want '1.0.0 '" >&2
  exit 1
fi
echo "oracle: dependency:tree resolves exactly com.example:formatter:1.0.0"

# ---- 3. restore the conflict on a copy; the enforcer must kill validate
rm -rf /tmp/oracle-neg
cp -r /app/service /tmp/oracle-neg
python3 /solution/neutralize.py /tmp/oracle-neg/pom.xml
if ( cd /tmp/oracle-neg && mvn -q -B "${M[@]}" validate ); then
  echo "oracle: reintroduced conflict did NOT fail validate -- the enforcer rule is ineffective" >&2
  exit 1
fi
rm -rf /tmp/oracle-neg
echo "oracle: reintroduced conflict fails validate (enforcer rule fires)"
echo "oracle: reference fix installed and proven"