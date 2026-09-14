# pylint: disable=missing-docstring,deprecated-typing-alias
# Corner shapes around the empty-tuple trigger: typing-module aliases (which do
# not crash on Python 3.12 but must keep checking cleanly), empty-tuple
# subscripts nested inside other subscripts, and a plain three-argument
# subscript that must not produce any message.
import typing as t
import collections.abc as ca

a: t.Generator[()]
b: t.AsyncGenerator[()]
c: ca.Generator[()]
d: tuple[ca.AsyncGenerator[()], ca.Generator[()]]
e: list[ca.Generator[()]]

plain: ca.Generator[int, str, str]