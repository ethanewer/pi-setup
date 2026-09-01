#!/usr/bin/env bash
mkdir -p /logs/verifier

reward=0
BIN=/app/cross/hello_arm
if [ -f "$BIN" ]; then
  finfo=$(file "$BIN" 2>/dev/null)
  # e_machine field of the ELF header (offset 18, little-endian u16):
  # AArch64 = 0xB7, x86-64 = 0x3E
  emachine=$(od -An -tx1 -j18 -N2 "$BIN" 2>/dev/null | tr -d ' \n')
  echo "$finfo" | grep -q 'ARM aarch64' || true
  aarch=0
  if echo "$finfo" | grep -q 'ARM aarch64' && echo "$finfo" | grep -q 'statically linked'; then
    aarch=1
  fi
  ehdr_ok=0
  if [ "$emachine" = "b700" ]; then
    ehdr_ok=1
  fi
  native=0
  if [ "$emachine" = "3e00" ]; then
    native=1
  fi
  target_ok=0
  if [ -f /app/cross/target.txt ] && [ "$(cat /app/cross/target.txt)" = "aarch64" ]; then
    target_ok=1
  fi
  if [ "$aarch" = 1 ] && [ "$ehdr_ok" = 1 ] && [ "$native" = 0 ] && [ "$target_ok" = 1 ]; then
    reward=1
  fi
fi
echo "$reward" > /logs/verifier/reward.txt