"""Hidden case for bracket-anchor: end-to-end cookie expiry semantics.

The upstream regression test only inspects CookieJar._parse_date.  This case
drives the full CookieJar.update_cookies path: a cookie whose Expires value is
a plausible FUTURE timestamp written in fullwidth or Arabic-Indic numerals must
be treated as an invalid date -- no expiration may be scheduled and the Expires
attribute must be cleared, so the cookie lives as a session cookie -- while an
equivalent ASCII value must still schedule an expiration at its exact instant.
"""

import datetime

import pytest
from http.cookies import SimpleCookie
from aiohttp import CookieJar
from yarl import URL

UTC = datetime.timezone.utc
FULLWIDTH = {d: chr(0xFF10 + d) for d in range(10)}  # ０-９
ARABIC = {d: chr(0x0660 + d) for d in range(10)}     # ٠-٩


def _expires_morsel(expires_value: str) -> SimpleCookie:
    c = SimpleCookie()
    c["sid"] = "abc"
    # Raw attribute value; the parser under test sees the unmodified string.
    c["sid"]["expires"] = expires_value
    return c


@pytest.mark.parametrize(
    "expires_value",
    [
        # fullwidth digits, future year: ２０３０
        "Tue, {} Jan {}{}{}{} 00:00:00 GMT".format(
            FULLWIDTH[1],
            FULLWIDTH[2], FULLWIDTH[0], FULLWIDTH[3], FULLWIDTH[0],
        ),
        # arabic-indic digits, future year: ٢٠٣٠
        "Tue, {} Jan {}{}{}{} 00:00:00 GMT".format(
            ARABIC[1],
            ARABIC[2], ARABIC[0], ARABIC[3], ARABIC[0],
        ),
    ],
)
def test_non_ascii_expires_is_a_session_cookie(expires_value: str) -> None:
    jar = CookieJar()
    jar.update_cookies(
        _expires_morsel(expires_value), URL("http://example.com/")
    )

    # The invalid date must not be accepted: nothing may be scheduled.
    assert jar._expirations == {}
    # The Expires attribute must have been rejected and cleared.
    (cookie,) = jar.cookies.values()
    assert cookie["sid"]["expires"] == ""
    # The cookie itself survives as a session cookie.
    assert "sid" in jar.filter_cookies(URL("http://example.com/"))


def test_equivalent_ascii_expires_still_schedules_exactly() -> None:
    ts = datetime.datetime(2030, 1, 1, tzinfo=UTC).timestamp()
    jar = CookieJar()
    jar.update_cookies(
        _expires_morsel("Tue, 1 Jan 2030 00:00:00 GMT"),
        URL("http://example.com/"),
    )
    assert list(jar._expirations.values()) == [ts]