"""Hidden case 3 for conduit-anchor: routing of datetime/timedelta scalars
through sequence/mapping comparisons beyond the upstream regression inputs.

The upstream regression tests for this bug cover list and dict containers
with whole-second values; these use tuples, a mapping with more than one
entry, a mapping whose values mix plain numbers with timedeltas, and
datetimes with fractional seconds, so the scalar-routing fix must genuinely
generalize.
"""
from datetime import datetime, timedelta

import pytest


def test_timedeltas_in_tuple():
    assert (timedelta(seconds=105), timedelta(minutes=2)) == pytest.approx(
        (timedelta(seconds=100), timedelta(minutes=2)), rel=0.05
    )
    assert (timedelta(seconds=110), timedelta(minutes=2)) != pytest.approx(
        (timedelta(seconds=100), timedelta(minutes=2)), rel=0.05
    )


def test_mapping_with_multiple_entries():
    assert {
        "first": timedelta(seconds=105),
        "second": timedelta(seconds=100),
    } == pytest.approx(
        {
            "first": timedelta(seconds=100),
            "second": timedelta(seconds=104),
        },
        rel=0.05,
    )
    # 20 seconds away from 100s is 20%, outside the 5% window
    assert {"a": timedelta(seconds=120)} != pytest.approx(
        {"a": timedelta(seconds=100)}, rel=0.05
    )


def test_mapping_with_mixed_value_kinds():
    # mappings may hold plain numbers next to timedeltas; each element routes
    # to the right comparison class
    assert {
        "elapsed": timedelta(seconds=105),
        "ratio": 1.0,
    } == pytest.approx(
        {
            "elapsed": timedelta(seconds=100),
            "ratio": 1.0 + 1e-9,
        },
        rel=0.05,
    )


def test_datetimes_in_tuple_with_abs():
    start = datetime(2024, 6, 1, 12, 0, 0)
    assert (datetime(2024, 6, 1, 12, 0, 0, 600_000),) == pytest.approx(
        (start,), abs=timedelta(seconds=1)
    )
    assert (datetime(2024, 6, 1, 12, 0, 5),) != pytest.approx(
        (start,), abs=timedelta(seconds=1)
    )