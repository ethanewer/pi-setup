"""Hidden case for bracket-anchor: RFC 6265 date formats must survive.

Guard case: the fix must restrict character classes, not the accepted date
shapes.  All three date formats RFC 6265 section 5.1.1 permits, including the
two-digit year and asctime layouts, must keep parsing to their exact ASCII
timestamps after the fix, exactly as they did before it.
"""

import datetime

from aiohttp import CookieJar

UTC = datetime.timezone.utc
WANT = datetime.datetime(1994, 11, 6, 8, 49, 37, tzinfo=UTC).timestamp()


def test_rfc6265_formats_unchanged() -> None:
    parse = CookieJar._parse_date
    # RFC 6265 example 1: IMF-fixdate (comma, 4-digit year)
    assert parse("Sun, 06 Nov 1994 08:49:37 GMT") == WANT
    # RFC 6265 example 2: rfc850 (weekday with ',', '-' separators, 2-digit year)
    assert parse("Sunday, 06-Nov-94 08:49:37 GMT") == WANT
    # RFC 6265 example 3: asctime (no commas, 2-digit year)
    assert parse("Sun Nov  6 08:49:37 1994") == WANT