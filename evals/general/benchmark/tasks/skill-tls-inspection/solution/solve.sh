#!/bin/bash
set -euo pipefail
# The certificate's subject CN is internal.probe.example
echo -n "internal.probe.example" > /app/answer.txt
echo "wrote /app/answer.txt"