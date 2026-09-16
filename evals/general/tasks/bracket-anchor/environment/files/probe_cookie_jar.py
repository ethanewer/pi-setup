#!/usr/bin/env python3
"""Exploratory probe for the cookie expiry parser in the /app/src aiohttp checkout.

Prints what the RFC 6265 date parser returns for several Expires values.
A date whose digits are all non-ASCII should be rejected (None) but in this
checkout is accepted as a concrete timestamp instead.
"""

from aiohttp import CookieJar

SAMPLES = [
    "Tue, 1 Jan 1970 00:00:00 GMT",  # plain ASCII epoch
    "Tue, ١ Jan ١٩٧٠ ٠٠:٠٠:٠٠ GMT",  # Arabic-Indic digits
    "Tue, １ Jan １９７０ ００:００:００ GMT",  # fullwidth digits
    "Tue, १ Jan १९७० ००:००:०० GMT",  # Devanagari digits
    "Tue, 1 Jan 1970 ٠٠:٠٠:٠٠ GMT",  # Arabic-Indic digits in the time only
    "Sun, 06 Nov 1994 08:49:37 GMT",  # plain ASCII, RFC 6265 example
]

for sample in SAMPLES:
    print(f"{CookieJar._parse_date(sample)!r} <- {sample}")