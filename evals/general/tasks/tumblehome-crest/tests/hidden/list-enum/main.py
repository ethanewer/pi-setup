from enum import Enum

class Tone(Enum):
    ON = 1

def apply(tones: list[Tone]) -> None:
    active: list[Tone] = []
    for t in tones:
        if t not in active:
            active.append(t)