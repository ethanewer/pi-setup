#!/usr/bin/env python3
import datetime
import os
import sys

sys.path.insert(0, os.environ.get("FREEZEGUN_SOURCE", "/app/freezegun_base"))
from freezegun import freeze_time


def main() -> int:
    calls = []

    try:
        @freeze_time("2012-01-14", as_arg=True)
        def positional(factory, number, *, label):
            calls.append(("arg", factory.time_to_freeze, number, label))

        positional(7, label="ok")

        @freeze_time("2013-02-15", as_kwarg="frozen")
        def keyword(number, *, frozen):
            calls.append(("kw", frozen.time_to_freeze, number))

        keyword(9)
    except Exception:
        pass
    ok = calls == [
        ("arg", datetime.datetime(2012, 1, 14), 7, "ok"),
        ("kw", datetime.datetime(2013, 2, 15), 9),
    ]
    print(f"BUILT {'PASS' if ok else 'FAIL'}")
    print(f"CALLS {len(calls)}")
    return 0 if ok and len(calls) == 2 else 1


if __name__ == "__main__":
    raise SystemExit(main())
