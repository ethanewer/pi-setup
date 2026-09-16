import datetime
import os
import sys

sys.path.insert(0, os.environ.get("FREEZEGUN_SOURCE", "/app/freezegun_base"))
from freezegun import freeze_time

with freeze_time("2022-07-08 09:10:11"):
    assert datetime.datetime.now() == datetime.datetime(2022, 7, 8, 9, 10, 11)
    assert datetime.date.today() == datetime.date(2022, 7, 8)

@freeze_time("2023-08-09")
def ordinary_decorator():
    assert datetime.datetime.now() == datetime.datetime(2023, 8, 9)
    return datetime.date.today()

assert ordinary_decorator() == datetime.date(2023, 8, 9)
