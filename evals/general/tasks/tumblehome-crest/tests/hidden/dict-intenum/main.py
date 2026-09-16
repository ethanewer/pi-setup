from enum import IntEnum

class Bit(IntEnum):
    ZERO = 0

def pack(bits: list[Bit]) -> None:
    acc: dict[Bit, int] = {}
    for b in bits:
        if b not in acc:
            acc[b] = 0
        acc[b] += 1