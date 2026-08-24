#!/bin/bash
set -euo pipefail
mkdir -p /home/user/.setup_tmp
export PYTHONPATH=/home/user/.local/lib/python3/dist-packages:${PYTHONPATH:-}
    python3 -c "
import struct
import os
records = [
    (100, 12345, 1),
    (100, 12345, 2),
    (100, 12345, 3),
    (100, 12345, 4),
    (100, 54321, 1),
    (101, 12345, 1),
    (101, 54321, 1),
    (101, 54321, 2),
    (101, 54321, 3),
    (101, 54321, 4),
    (101, 54321, 5),
]
bin_path = '/home/user/requests.bin'
exp_path = '/home/user/expected_results.txt'
with open(bin_path, 'wb') as f_bin, open(exp_path, 'w') as f_exp:
    counts = {}
    current_ts = None
    for ts, ip, ep in records:
        f_bin.write(struct.pack('<IIH', ts, ip, ep))
        if ts != current_ts:
            current_ts = ts
            counts = {}
        counts[ip] = counts.get(ip, 0) + 1
        status = 'ACCEPTED' if counts[ip] <= 3 else 'REJECTED'
        f_exp.write(f'{ts} {ip} {status}\n')
os.chmod(bin_path, 0o644)
os.chmod(exp_path, 0o644)
"
rm -rf /home/user/.setup_tmp
