from typing import Type, TypeVar, Union


class Rabbit:
    def __init__(self, name: str = "") -> None:
        pass


class Squirrel:
    def __init__(self, name: str = "") -> None:
        pass


class Fox:
    def __init__(self, name: str = "") -> None:
        pass


T = TypeVar("T", bound=Union[Rabbit, Union[Squirrel, Fox]])


def create(ftype: Type[T], name: str) -> T:
    if name:
        return ftype(name=name)
    return ftype()
