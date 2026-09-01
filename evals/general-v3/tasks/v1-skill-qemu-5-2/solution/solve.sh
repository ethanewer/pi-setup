#!/bin/bash
set -euo pipefail
printf '%s\n' 'qemu-system-x86_64 -m 2048 -smp 2 -drive file=/app/guest.iso,media=cdrom -boot order=cd' > /app/qemu_boot.txt
echo wrote qemu_boot.txt
