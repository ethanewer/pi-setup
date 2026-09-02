#!/bin/bash
# Oracle for juniper-yonder. Installs the solver as /app/attack.py and runs it
# on the shipped workspace to actually produce the deliverables. Real work;
# never reads /tests and never cats a precomputed answer.
set -eu

cp /solution/attack.py /app/attack.py
chmod +x /app/attack.py

rm -f /app/keys /app/plaintexts.txt /app/name.txt /app/decoded_names.txt /app/passcode.txt
rm -rf /app/encsrc

python3 /app/attack.py /app/workspace /app

echo "oracle produced deliverables in /app"
