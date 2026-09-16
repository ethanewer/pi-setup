import datetime
import os
import sys

sys.path.insert(0, os.environ.get("FREEZEGUN_SOURCE", "/app/freezegun_base"))
from freezegun import freeze_time

seen = []

@freeze_time("2020-03-04", as_arg=True)
def decorated(factory, value, *, marker):
    seen.append((factory.time_to_freeze, value, marker))
    return factory

factory = decorated(42, marker="hidden")
assert factory.time_to_freeze == datetime.datetime(2020, 3, 4)
assert seen == [(datetime.datetime(2020, 3, 4), 42, "hidden")]

@freeze_time("2020-03-04", as_arg=True)
def generated(factory, value):
    yield factory.time_to_freeze, value

assert list(generated("g")) == [(datetime.datetime(2020, 3, 4), "g")]
