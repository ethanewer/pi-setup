from typing import Type, TypeVar, Union


class Bytes:
    def __init__(self, size: int = 0) -> None:
        pass


class Pages:
    def __init__(self, size: int = 0) -> None:
        pass


T = TypeVar("T", bound=Union[Bytes, Pages])


class Factory:
    def build(self, ftype: Type[T], size: int) -> T:
        if size:
            return ftype(size)
        return ftype()
