import datetime
import os
import sys

sys.path.insert(0, os.environ.get("FREEZEGUN_SOURCE", "/app/freezegun_base"))
from freezegun import freeze_time

calls = []

@freeze_time("2021-05-06", as_kwarg="clock")
def decorated(first, *, clock, second="default"):
    calls.append((first, clock.time_to_freeze, second))

decorated("left", second="right")
assert calls == [("left", datetime.datetime(2021, 5, 6), "right")]

try:
    @freeze_time("2021-05-06", as_arg=True, as_kwarg="clock")
    def invalid(factory, *, clock):
        return factory, clock
    invalid()
except AssertionError:
    pass
else:
    raise AssertionError("both injection modes must remain rejected")
