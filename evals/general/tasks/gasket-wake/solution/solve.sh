#!/bin/bash
# Oracle for gasket-wake: applies gin's upstream fix for the
# case-insensitive fixed-path lookup panic (issue #4535, fix commit
# 472d086a...) to /app/src/tree.go, writes the reproduction deliverable,
# and proves the reproduction plus the project's own regression tests and
# full suite against the repaired tree.
set -e

export PATH=/usr/local/go/bin:$PATH
export GO111MODULE=on

echo "== apply the fix =="
python3 /solution/fix_tree.py /app/src/tree.go

echo "== write the reproduction deliverable =="
cp /solution/repro_caseinsensitive_test.go /app/repro_caseinsensitive_test.go

echo "== reproduction against the repaired tree =="
cp /app/repro_caseinsensitive_test.go /app/src/
(cd /app/src && go test -v github.com/gin-gonic/gin \
  -test.run 'TestReproCaseInsensitivePath(StaticAndParam|NotFound)')
rm -f /app/src/repro_caseinsensitive_test.go

echo "== upstream regression tests extracted from the fix commit =="
rm -rf /tmp/oracle-golden
cp -a /app/src /tmp/oracle-golden
cp /opt/golden/tree_test.go /tmp/oracle-golden/tree_test.go
(cd /tmp/oracle-golden && go test -v github.com/gin-gonic/gin \
  -test.run 'TestTreeFindCaseInsensitivePath(WithMultipleChildrenAndWildcard|WildcardParamAndStaticChild)')
rm -rf /tmp/oracle-golden

echo "== the project's own full suite =="
(cd /app/src && go test -v github.com/gin-gonic/gin)
(cd /app/src && go test -v github.com/gin-gonic/gin/binding)
(cd /app/src && go test -v github.com/gin-gonic/gin/render)

echo "== final tree state (must show only tree.go modified) =="
cd /app/src && git status --porcelain