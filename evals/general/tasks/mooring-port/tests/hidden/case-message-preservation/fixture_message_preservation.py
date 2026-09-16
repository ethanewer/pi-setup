# pylint: disable=missing-docstring
# The extension's own check must keep working after the fix: None-default
# subscripts in non-module positions still emit unnecessary-default-type-args
# with the shortened suggestion.
import collections.abc as ca
from collections.abc import AsyncGenerator


def check() -> None:
    a: ca.Generator[int, None, None]
    b: ca.AsyncGenerator[int, None]


class C:
    attr: ca.Generator[int, None, None]

    def method(self) -> ca.AsyncGenerator[int, None]:
        return NotImplemented