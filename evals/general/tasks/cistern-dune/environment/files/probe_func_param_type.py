#!/usr/bin/env python3
"""Show the BadParameter message click produces for FuncParamType values whose
conversion function raises ValueError.

At the pinned (buggy) commit, the ValueError's own message is discarded and the
raw input value is echoed back instead, so both lines print 'nope'.  After the
correct fix, the first line prints 'bad value: nope' (the ValueError message)
and the second still prints 'nope' (the raw-input fallback for an empty
ValueError message).
"""

import click


def with_message(value):
    raise ValueError("bad value: nope")


def empty_message(value):
    raise ValueError()


def main() -> None:
    for label, func in (
        ('ValueError("bad value: nope")', with_message),
        ("ValueError() (empty message)", empty_message),
    ):
        t = click.types.FuncParamType(func)
        try:
            t.convert("nope", None, None)
        except click.BadParameter as e:
            print(f"value 'nope' + {label} -> BadParameter message: {e.message!r}")


if __name__ == "__main__":
    main()