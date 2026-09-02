#!/bin/bash
set -euo pipefail
gcc -O2 -o /app/host/probe /app/host/probe.c
/app/host/probe > /app/host/abi.txt