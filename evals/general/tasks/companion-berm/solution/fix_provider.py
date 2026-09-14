#!/usr/bin/env python3
"""Oracle helper: repair src/poetry/puzzle/provider.py == fix for #10805.

The upstream fix (parent -> fix b8383e3c) wraps the yield in Indicator.context()
in try/finally so the class-level Indicator.CONTEXT is always cleared, including
when the body of the with-block raises. We apply exactly that transformation and
fail loudly if the source does not match the expected (buggy) shape first.
"""
import sys

SRC = """        yield _set_context

        _set_context(None)
"""
DST = """        try:
            yield _set_context
        finally:
            _set_context(None)
"""


def main() -> int:
    path = sys.argv[1] if len(sys.argv) > 1 else '/app/src/src/poetry/puzzle/provider.py'
    with open(path) as f:
        text = f.read()
    if SRC in text:
        text = text.replace(SRC, DST)
        with open(path, 'w') as f:
            f.write(text)
        print(f'fixed {path}: wrapped Indicator.context() yield in try/finally')
        return 0
    if DST in text:
        print(f'{path} already carries the fix; nothing to do')
        return 0
    raise SystemExit(f'unexpected provider.py shape; cannot apply the fix (no expected yield pattern found)')


if __name__ == '__main__':
    raise SystemExit(main())
