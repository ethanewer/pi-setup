# Cookie expiry dates must be ASCII-only

## Situation

`/app/src` is a shallow, pinned clone of the aiohttp project
(`https://github.com/aio-libs/aiohttp`), checked out at upstream commit
`58bae08b7e4831c6c184fe22233bfc19941c700b`, and installed from that tree in
editable (development) mode with the C extensions disabled, so the code you
import is exactly the checked-out Python source. Python 3.12, pytest, and the
pytest plugins the project's own test configuration needs are installed.
There is **no network** at trial time: everything you need is already in the
image; `pip` and `git fetch` will not work.

## The bug

When a cookie arrives with an `Expires` attribute, aiohttp parses that date
using a HTTP-date parser that follows RFC 6265 section 5.1.1. That section
requires the date to be **pure ASCII**. The parser in this checkout does not
enforce that: its digit matching accepts *any* Unicode decimal digit, not just
the ASCII digits `0`-`9`.

The result: a `Set-Cookie`-style `Expires` value whose date contains non-ASCII
digits -- for example Arabic-Indic numerals (`٠١٢٣٤٥٦٧٨٩`), fullwidth numerals
(`０１２３４５６７８９`), or Devanagari numerals (`०१२३४५६७८९`) -- is accepted
as a valid expiry timestamp instead of being rejected. The cookie then gets a
concrete expiration time (it is scheduled to expire at the parsed time and its
`Expires` attribute is kept) when it should instead be treated as a session
cookie with the invalid date rejected.

## Reproducing the failure

```
python3 /app/probe_cookie_jar.py
```

prints what the parser returns for several dates. For a date whose digits are
all non-ASCII the parser prints an integer timestamp where it should print
`None`.

A one-liner that shows the same thing:

```
python3 -c "from aiohttp import CookieJar; print(repr(CookieJar._parse_date('Tue, ١ Jan ١٩٧٠ ٠٠:٠٠:٠٠ GMT')))"
```

## What you need to do

Fix the bug in the checked-out tree at `/app/src` so that cookie expiry dates
containing non-ASCII digits are rejected (the date parser returns `None` for
them), exactly as RFC 6265 requires, **without changing the accepted semantics
of any ASCII date**. An ASCII date such as `Tue, 1 Jan 1970 00:00:00 GMT`
must still parse exactly as it does today.

Drive your work with the project's own test runner, from `/app/src`:

```
cd /app/src && python3 -m pytest tests/test_cookiejar.py -q -p no:cacheprovider
```

The whole existing cookie-jar test file is green at the pinned commit; keep it
that way. Add your own tests if that helps you verify (for example cases with
other digit scripts, or a full cookie with a non-ASCII `Expires` value flowing
through `CookieJar.update_cookies`), but the verdict on your fix is made by the
verifier, which also runs checks its own way.

## Constraints

- Network is unavailable; everything needed is installed already.
- The clone is the deliverable. Change only what the fix requires, in place.
  Do not rewrite history, add remotes, fetch, or change build files. Files
  under `/opt/golden`, `/tests` and `/solution` are harness-owned; do not touch
  them.
- The verifier also asserts that the working tree remains at the pinned commit,
  that no other tracked files were modified, and that no new files were added
  inside the aiohttp package.

## What the verifier checks

1. The tree is still at commit `58bae08b7e4831c6c184fe22233bfc19941c700b`, no
   extra tracked files were changed, and the repair touches only the minimal
   source surface.
2. The project's upstream regression test for this behaviour passes.
3. The project's own existing cookie-jar tests still pass.
4. Hidden cases over inputs the upstream test does not use pass, including
   other non-ASCII digit scripts at the parser level and the full
   `CookieJar.update_cookies` path where a non-ASCII `Expires` value must be
   rejected and the cookie stored as a session cookie (no scheduled
   expiration, `Expires` attribute cleared).

Deliverable: the repaired `/app/src` tree.