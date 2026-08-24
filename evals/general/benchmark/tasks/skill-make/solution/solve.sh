#!/bin/bash
set -euo pipefail
cd /app
cat > Makefile <<'EOF'
hello: src/main.c
	gcc -O2 -o hello src/main.c
EOF
make
./hello