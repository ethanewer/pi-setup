from enum import Enum

class Flag(Enum):
    UP = 1

def route(flags: list[Flag]) -> int:
    seen: set[Flag] = set()
    total = 0
    for f in flags:
        if f not in seen:
            seen.add(f)
            total += 1
    return total