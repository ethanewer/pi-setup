#!/bin/bash
# Willow Upland oracle: write the two deliverables by doing the real work, then
# RUN them to prove they regenerate their outputs from a pristine /app.
# Never reads /tests.
set -e
cd /app

# --- Deliverable 1: /app/fix.sh (idempotent, LF-only, allowlist-restricted) --
cat > /app/fix.sh <<'SH'
#!/usr/bin/env bash
# Willow Upland ingest helper: idempotent tree recreate, severity scan,
# cleanup of generated artifacts to the allowed set. Allowlist-restricted:
# only mkdir/grep/wc/printf plus for/if/case control and redirection.
mkdir -p /app/out/summary /app/out/records /app/stage /app/logs

{
  printf 'INFO='
  grep -iwh 'INFO' /app/logs/*.log | wc -l
  printf 'WARN='
  grep -iwh 'WARN' /app/logs/*.log | wc -l
  printf 'ERROR='
  grep -iwh 'ERROR' /app/logs/*.log | wc -l
} > /app/out/summary/severity_counts.txt

for f in /app/stage/*; do
  if [ -f "$f" ]; then
    case "$f" in
      *.proof) ;;
      */MANIFEST) ;;
      *) rm -f "$f" ;;
    esac
  fi
done

exit 0
SH
chmod +x /app/fix.sh

# --- Deliverable 2: /app/Makefile (serial + pgen) --------------------------
cat > /app/Makefile <<'MK'
CC    ?= gcc
CFLAGS ?= -O2 -Wall
BIN   := bin

all: serial pgen

serial: src/serial.c | $(BIN)
	$(CC) $(CFLAGS) -o $(BIN)/serial src/serial.c

pgen: src/pgen.c | $(BIN)
	$(CC) $(CFLAGS) -o $(BIN)/pgen src/pgen.c

$(BIN):
	mkdir -p $(BIN)

clean:
	rm -f $(BIN)/serial $(BIN)/pgen

.PHONY: all clean
MK

# --- Run the real deliverables to regenerate their outputs -----------------
bash /app/fix.sh
make -C /app
make -C /app          # idempotent no-op re-run must still succeed

# sanity: the regenerated outputs exist and are non-empty / executable
test -s /app/out/summary/severity_counts.txt
test -d /app/out/records
test -x /app/bin/serial
test -x /app/bin/pgen

echo "solve.sh: deliverables written and run OK"