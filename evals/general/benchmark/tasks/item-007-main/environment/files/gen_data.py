#!/usr/bin/env python3
"""Deterministic stand-alone generator identical to the shipped train.bin."""
import sys, os
os.makedirs("data", exist_ok=True)
with open("data/train.bin", "wb") as f:
    for i in range(200):
        lab = i % 10
        raw = bytearray([lab])
        for y in range(32):
            for x in range(32):
                for ch in range(3):
                    raw.append((x * 3 + y * 7 + ch * 11 + lab * 40) % 256)
        f.write(raw)
print("generated data/train.bin")
