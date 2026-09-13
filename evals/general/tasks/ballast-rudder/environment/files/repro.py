from typing import Any, TypeVar, overload

T = TypeVar("T")


@overload
def f(value: T) -> tuple[T, int]: ...
@overload
def f(*values: object) -> tuple[Any, ...]: ...
def f(*values: object, **kwargs: object) -> object: ...


def g() -> None:
    first: str
    first, second = f(1)