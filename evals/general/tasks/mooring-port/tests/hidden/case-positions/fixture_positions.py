# pylint: disable=missing-docstring
# Empty-tuple type-argument subscripts in code positions the upstream
# regression test does not use: return annotations, function-body annotations,
# direct imports, class attributes, and subscripts nested inside other
# subscripts.
import collections.abc as ca
from collections.abc import AsyncGenerator


def make() -> ca.Generator[()]:
    """Empty-tuple subscript in a return annotation."""


def check() -> None:
    local: ca.AsyncGenerator[()]
    if True:
        inner: ca.Generator[()]
    return None


class C:
    attr: ca.Generator[()]

    def method(self) -> ca.Generator[()]:
        return self


boxes: list[ca.Generator[()]] = []

pairs: tuple[ca.AsyncGenerator[()], ca.Generator[()]]