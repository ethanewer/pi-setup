#!/bin/bash
# Oracle for cistern-flood: applies the upstream domain-boundary fix to the
# requests checkout at /app/src (mirror of the bpo-39057 change), re-checks
# the reproduction in both directions, and runs the upstream regression test
# extracted into /opt/golden/ at image build time.
set -e

python3 /solution/fix_should_bypass.py /app/src/src/requests/utils.py

echo "== reproduction after the fix (expected: False, True) =="
python3 -c "from requests.utils import should_bypass_proxies; print(should_bypass_proxies('http://prelocalhost/', no_proxy='localhost')); print(should_bypass_proxies('http://d.o.t/', no_proxy='.d.o.t'))"

first=$(python3 -c "from requests.utils import should_bypass_proxies; print(should_bypass_proxies('http://prelocalhost/', no_proxy='localhost'))")
second=$(python3 -c "from requests.utils import should_bypass_proxies; print(should_bypass_proxies('http://d.o.t/', no_proxy='.d.o.t'))")
test "$first" = "False"
test "$second" = "True"

echo "== upstream regression test =="
cd /app/src
python3 -m pytest /opt/golden/pkg/test_utils.py::test_should_bypass_proxies_no_proxy_domain_boundary -q -p no:cacheprovider -o addopts=