from typing import Optional

def strip_none(x: Optional[int]) -> int:
    if x not in (None,):
        return x
    return 0