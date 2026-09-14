from typing import Type, TypeVar, Union


class Point:
    def __init__(self, x: int = 0, y: int = 0) -> None:
        pass


class Pair:
    def __init__(self, x: int = 0, y: int = 0) -> None:
        pass


T = TypeVar("T", bound=Union[Point, Pair])


def origin_or(ftype: Type[T], x: int, y: int) -> T:
    if x == 0 and y == 0:
        return ftype()
    return ftype(x, y)
