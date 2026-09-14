"""Hidden case 1 (luff-yard): parameterless WWW-Authenticate challenges must
serialize to a bare, title-cased scheme with NO trailing whitespace, across
schemes the upstream regression test does not use (including case variants),
and the serialized value must satisfy the strict single-token grammar of
RFC 9110 — the exact property a strict HTTP/1.1 client (e.g. h11) enforces.

Fails on the pre-fix tree ('Bearer ' etc.); passes once the serialization is
repaired. Runs against the agent's tree via confcutdir isolation, importing
werkzeug from /app/src.
"""
import re

import pytest

from werkzeug.datastructures import WWWAuthenticate

# RFC 9110 token grammar: 1*tchar, no whitespace allowed.
TOKEN = re.compile(r"[!#$%&'*+\-.^_`|~0-9A-Za-z]+\Z")

SCHEMES = ["basic", "digest", "negotiate", "custom-scheme", "app-acme.v2"]


@pytest.mark.parametrize("scheme", SCHEMES)
def test_parameterless_challenge_is_bare_scheme(scheme):
    wa = WWWAuthenticate(scheme)
    # genuinely parameterless: no parameters dict entries, no token
    assert dict(wa.parameters) == {}
    assert wa.token is None
    out = wa.to_header()
    expected = scheme.title()
    assert out == expected
    assert out == out.rstrip()
    assert not out.endswith(" ")
    # a strict token-only parser must accept the whole value
    assert TOKEN.fullmatch(out), out


@pytest.mark.parametrize(
    "scheme,expected",
    [("BEARER", "Bearer"), ("Basic", "Basic"), ("DiGeSt", "Digest")],
)
def test_case_variants(scheme, expected):
    assert WWWAuthenticate(scheme).to_header() == expected


def test_all_schemes_pass_strict_token_grammar():
    for scheme in SCHEMES:
        out = WWWAuthenticate(scheme).to_header()
        assert TOKEN.fullmatch(out), out
        assert len(out) == len(out.strip())