#!/usr/bin/env python3
"""Generate the hidden cases for marl-haven (run once at authoring time).

Each case is a directory under tests/hidden with capture.bin + query.txt.
The verifier re-derives expected matrices independently, so no expected
files are stored here.
"""
import os
import struct

HERE = os.path.dirname(os.path.abspath(__file__))


def build_capture(path, key, flags, statuses, channels, base, step):
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
            out += b"\x00" * (2 * channels)
    with open(path, "wb") as fh:
        fh.write(bytes(out))


def write_case(name, key, flags, statuses, channels, base, step, query_lines):
    d = os.path.join(HERE, "hidden", name)
    os.makedirs(d, exist_ok=True)
    build_capture(os.path.join(d, "capture.bin"), key, flags, statuses,
                  channels, base, step)
    with open(os.path.join(d, "query.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(query_lines) + "\n")
    print("wrote", name)


# case_delta_invalid: delta-encoded, nonzero key, invalid frames interleaved,
# duplicate frame indices (row 6 twice) and a reversed channel range.
write_case(
    "case_delta_invalid",
    key=0xC3, flags=1,
    statuses=[1, 0, 1, 1, 0, 1, 1, 0, 1],   # 6 valid frames
    channels=3, base=[300, -1200, 25000], step=[7, 12, -9],
    query_lines=["channels=0-1,2,0", "frames=6,3,0-3"],  # 6 out-of-range (ignored); 3 duplicated
)

# case_plain: no delta, key 0, single channel, out-of-order single-token rows,
# out-of-range indices (>= 6) ignored.
write_case(
    "case_plain",
    key=0x00, flags=0,
    statuses=[1, 1, 1, 1, 1, 1],
    channels=1, base=[-32000], step=[5000],
    query_lines=["channels=0", "frames=5,0,3-4,7-9"],
)

# case_all_invalid: every frame invalid -> zero rows selected; matrix must be
# (0, 2).
write_case(
    "case_all_invalid",
    key=0xAB, flags=1,
    statuses=[0, 0, 0, 0, 0],
    channels=2, base=[100, -100], step=[3, -5],
    query_lines=["channels=1,0", "frames=0-3"],
)
