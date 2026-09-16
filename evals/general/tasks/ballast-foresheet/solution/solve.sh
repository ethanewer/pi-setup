#!/bin/bash
# Oracle for ballast-foresheet: applies the minimal upstream-style fix to the
# Hugo checkout at /app/src (make the IP-literal URL deny rule case-insensitive
# and gate dial-time addresses on an isPublicAddr helper that unwraps NAT64 and
# denies CGNAT/TEST-NET/benchmarking/reserved/documentation ranges), then runs
# the project's own regression tests for this bug against the repaired tree.
set -e

python3 /solution/fix_security_go.py /app/src/config/security/securityConfig.go

echo "== running the overlaid upstream regression tests against the repaired tree =="
cd /app/src && go test -vet=off ./config/security \
  -run 'TestCheckAllowedHTTPURLHardenedDefaultsIssue14792|TestCheckAllowedHTTPAddress' \
  -count=1 -v

echo "== full config/security suite =="
go test -vet=off ./config/security -count=1