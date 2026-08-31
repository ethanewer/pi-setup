#!/bin/bash
# Oracle for pumice-core: install the reference VM and RUN it on the visible
# sample to produce /app/sample_out.txt. Never reads /tests.
set -eu

cp /solution/vm.js /app/vm.js
chmod +x /app/vm.js

node /app/vm.js /app/samples/boot.elf > /app/sample_out.txt
echo "solve.sh done"
ls -l /app/vm.js /app/sample_out.txt
cat /app/sample_out.txt
