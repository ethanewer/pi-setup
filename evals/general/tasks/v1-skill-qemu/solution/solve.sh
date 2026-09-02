#!/bin/bash
set -euo pipefail
printf '%s\n' 'qemu-system-x86_64 -m 8192 -smp 4 -drive file=/app/guest.img,format=raw -display none' > /app/qemu_cmd.txt
echo wrote qemu_cmd.txt
