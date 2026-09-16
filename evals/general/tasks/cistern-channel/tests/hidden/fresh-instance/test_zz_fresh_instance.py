"""Hidden case 2: a FRESH parser created AFTER a mutation.

The upstream regression test creates both parsers before mutating one of
them. This case mutates first and only then creates the second parser: the
class-level default must not have been corrupted by the earlier mutation, so
the brand-new parser still starts from the full default handler set.
"""
import falcon
from falcon.media.multipart import MultipartParseOptions


def test_fresh_parser_created_after_mutation_is_unaffected():
    first = MultipartParseOptions()
    first.media_handlers.pop(falcon.MEDIA_JSON)
    assert len(first.media_handlers) == 1

    second = MultipartParseOptions()
    assert falcon.MEDIA_JSON in second.media_handlers
    assert len(second.media_handlers) == 2
    assert first.media_handlers is not second.media_handlers

    # the default set must still be the two built-in handlers
    assert set(second.media_handlers.keys()) == {
        falcon.MEDIA_JSON,
        falcon.MEDIA_URLENCODED,
    }