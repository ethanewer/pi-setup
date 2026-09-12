"""Hidden case for bracket-anchor: RFC 6265 expiry-date parsing.

The upstream regression test checks Arabic-Indic and fullwidth samples.  This
case builds the same code path from other Unicode decimal-digit scripts --
Devanagari, Bengali and Kannada -- in the day, year and time positions, and
guards that genuine ASCII dates still parse to their exact historic values.
"""

import datetime

import pytest
from aiohttp import CookieJar

UTC = datetime.timezone.utc

# Nd (decimal digit) scripts: Devanagari ०-९, Bengali ০-৯, Kannada ೦-೯.
DEVANAGARI = {d: chr(0x0966 + d) for d in range(10)}
BENGALI = {d: chr(0x09E6 + d) for d in range(10)}
KANNADA = {d: chr(0x0CE6 + d) for d in range(10)}

NON_ASCII_DATES = [
    # Devanagari digits in the day, year and time positions
    "Tue, {}, {} {}, {}:{}:{} GMT".format(
        DEVANAGARI[1], "19" + DEVANAGARI[7] + DEVANAGARI[0], "Jan",
        DEVANAGARI[0] + DEVANAGARI[2], DEVANAGARI[3], DEVANAGARI[4],
    ),
    # Bengali digits in the day and time positions (ASCII year)
    "Tue, {}, {} {}, {}:{}:{} GMT".format(
        BENGALI[2], "1970", "Jan",
        BENGALI[0] + BENGALI[0], BENGALI[1] + BENGALI[2], BENGALI[3] + BENGALI[4],
    ),
    # Kannada digits in the time position only
    "Tue, 1 Jan 1970 {}:{}:{} GMT".format(
        KANNADA[1] + KANNADA[2], KANNADA[4] + KANNADA[5], KANNADA[3] + KANNADA[0],
    ),
    # Devanagari digits in the year position only (no ASCII run to fall back on)
    "Tue, 1 Jan {} 00:00:00 GMT".format(
        DEVANAGARI[1] + DEVANAGARI[9] + DEVANAGARI[7] + DEVANAGARI[0]
    ),
]


@pytest.mark.parametrize("date_str", NON_ASCII_DATES)
def test_non_ascii_digit_dates_are_rejected(date_str: str) -> None:
    assert CookieJar._parse_date(date_str) is None


def test_ascii_dates_still_parse_exactly() -> None:
    parse = CookieJar._parse_date
    assert parse("Tue, 1 Jan 1970 00:00:00 GMT") == 0
    assert parse("Tue, 1 Jan 2030 00:00:00 GMT") == datetime.datetime(
        2030, 1, 1, tzinfo=UTC
    ).timestamp()
    assert parse("Sun, 06 Nov 1994 08:49:37 GMT") == datetime.datetime(
        1994, 11, 6, 8, 49, 37, tzinfo=UTC
    ).timestamp()