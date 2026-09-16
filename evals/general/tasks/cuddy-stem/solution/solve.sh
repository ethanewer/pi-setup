#!/bin/bash
# Oracle for cuddy-stem: applies the reserved-close-code fix to the aiohttp
# checkout (/app/src), writes the reproduction deliverable, and verifies that
# both behave before exiting.
set -e

python3 /solution/fix_reader.py /app/src/aiohttp/_websocket/reader_py.py

cp /solution/repro_impl.py /app/reproduce_issue.py
chmod +x /app/reproduce_issue.py

echo "== reproduction on the repaired tree =="
python3 /app/reproduce_issue.py

echo "== upstream regression test (extracted into /opt/golden at build time) =="
cd /app/src
cp tests/test_websocket_parser.py /tmp/oracle_parser_backup.py
cp /opt/golden/test_websocket_parser.py tests/test_websocket_parser.py
python3 -m pytest tests/test_websocket_parser.py::test_close_frame_reserved_code \
    -q -p no:cacheprovider
cp /tmp/oracle_parser_backup.py tests/test_websocket_parser.py

echo "== existing parser tests =="
python3 -m pytest tests/test_websocket_parser.py -q -p no:cacheprovider

echo "== existing writer tests =="
python3 -m pytest tests/test_websocket_writer.py -q -p no:cacheprovider