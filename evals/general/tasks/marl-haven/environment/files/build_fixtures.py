#!/usr/bin/env python3
"""Build the visible SBT-1 fixtures for marl-haven (run at image build).

Writes /app/capture.bin (binary telemetry capture, delta-encoded, with invalid
frames) and /app/query.txt. Deterministic; contains no answer material.
"""
import os
import struct

PARENT = "/app"


def build_capture(path, key, flags, statuses, channels, base, step):
    """statuses: list of 0/1; channels: C; true value of valid-frame k, ch c:
    base[c] + step[c]*k + ((k*(c+3)) % 7) - 3 (small wiggle, int16-safe)."""
    n = len(statuses)
    valid_pos = [i for i, s in enumerate(statuses) if s == 1]
    k_of = {pos: k for k, pos in enumerate(valid_pos)}

    def true_val(k, c):
        return base[c] + step[c] * k + ((k * (c + 3)) % 7) - 3

    out = bytearray()
    out += b"SBTF"
    out += struct.pack(">HBB", 1, key, flags)
    out += struct.pack(">I", n)
    out += struct.pack(">HH", channels, 0)
    for i in range(n):
        ts = 1700000000000 + 1000 * i
        out += struct.pack(">QB", ts, statuses[i])
        if statuses[i] == 1:
            k = k_of[i]
            deltas = []
            for c in range(channels):
                if k == 0:
                    deltas.append(true_val(0, c))
                else:
                    deltas.append(true_val(k, c) - true_val(k - 1, c))
            raw = b"".join(struct.pack(">h", d) for d in deltas)
            out += bytes(b ^ key for b in raw)
        else:
            # Invalid frames still occupy a full frame slot: payload bytes
            # (ignored by decoders) are zero-filled.
            out += b"\x00" * (2 * channels)
    with open(path, "wb") as fh:
        fh.write(bytes(out))


def main():
    os.makedirs(PARENT, exist_ok=True)

    # Visible capture: 12 frames, 4 channels, delta-encoded, key 0x5A,
    # invalid frames at absolute positions 2, 5, 7, 10 -> 8 valid frames.
    build_capture(
        os.path.join(PARENT, "capture.bin"),
        key=0x5A,
        flags=1,
        statuses=[1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1],
        channels=4,
        base=[1000, -500, 20000, 7],
        step=[10, -25, -4, 1],
    )

    # Visible query: reordered + duplicate-prone columns, mixed row tokens,
    # one out-of-range frame index (9 >= 8 valid) that must be ignored.
    with open(os.path.join(PARENT, "query.txt"), "w", encoding="utf-8") as fh:
        fh.write("channels=2,0,3-3,1\n")
        fh.write("frames=4,0-2,9\n")

    print("marl-haven fixtures written to", PARENT)


if __name__ == "__main__":
    main()
