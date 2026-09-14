"""Hidden case 2 (luff-yard): the fix must change ONLY the parameterless
serialization. Challenges that DO carry parameters or a token must keep
serializing exactly as they did before the fix — same quoting, same
ordering, same separators — and a challenge whose parameters are removed
must fall back to the clean bare scheme.

Passes on both the pre-fix tree and the repaired tree; it exists to catch a
fix that "works" by degrading the parameterised path.
"""
import pytest

from werkzeug.datastructures import WWWAuthenticate


def test_parameterised_basic_unchanged():
    assert (
        WWWAuthenticate("basic", {"realm": "Foo Bar"}).to_header()
        == 'Basic realm="Foo Bar"'
    )


def test_parameterised_digest_unchanged():
    assert (
        WWWAuthenticate(
            "digest",
            {"realm": "testrealm@host.com", "qop": "auth", "nonce": "abc"},
        ).to_header()
        == 'Digest realm="testrealm@host.com", qop="auth", nonce="abc"'
    )


def test_parameterised_bearer_unchanged():
    assert WWWAuthenticate("bearer", {"realm": "x"}).to_header() == "Bearer realm=x"


def test_token_challenge_unchanged():
    assert WWWAuthenticate("bearer", None, "abc").to_header() == "Bearer abc"


def test_removing_parameters_restores_bare_scheme():
    wa = WWWAuthenticate("bearer", {"realm": "x"})
    assert wa.to_header() == "Bearer realm=x"
    del wa["realm"]
    assert dict(wa.parameters) == {}
    assert wa.to_header() == "Bearer"


def test_from_header_with_params_round_trips():
    wa = WWWAuthenticate.from_header('Basic realm="Foo Bar"')
    assert wa.to_header() == 'Basic realm="Foo Bar"'
    wa2 = WWWAuthenticate.from_header(
        'Digest realm="testrealm@host.com", qop="auth", nonce="abc"'
    )
    assert wa2.to_header() == 'Digest realm="testrealm@host.com", qop="auth", nonce="abc"'