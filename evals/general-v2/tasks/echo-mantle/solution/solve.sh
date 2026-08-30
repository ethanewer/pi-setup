#!/usr/bin/env bash
# Oracle for echo-mantle: builds every deliverable by doing the real work.
set -euo pipefail

# 1. install the provisioning script as a deliverable
cp /solution/impl/setup.sh /app/setup.sh
chmod 0755 /app/setup.sh

# 2. the netflow parser
cp /solution/impl/pcap_to_netflow.py /app/pcap_to_netflow.py
chmod 0755 /app/pcap_to_netflow.py

# 3. capture the terminal ending text verbatim into the designated file
cat /app/fixtures/valediction.txt > /app/answer.txt

# 4. run the provisioning; the reporter writes /app/status.json itself
bash /app/setup.sh >/dev/null 2>&1
sleep 3

# 5. derive the flow table from the provided capture with the parser
python3 /app/pcap_to_netflow.py /app/fixtures/traffic.pcap /app/flows.json >/dev/null

exit 0