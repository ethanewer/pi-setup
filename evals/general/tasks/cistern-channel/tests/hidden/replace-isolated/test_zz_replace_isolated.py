"""Hidden case 1: handler REPLACEMENT (upstream regression test uses pop).

Makes sure that replacing the JSON handler on one parser's media_handlers
stays scoped to that parser: the second parser must keep its own default
handlers untouched, and the mutation must not leak into its resolution.
"""
import falcon
from falcon.media import JSONHandler
from falcon.media.multipart import MultipartParseOptions


def test_replacing_a_handler_on_one_parser_is_isolated():
    one = MultipartParseOptions()
    two = MultipartParseOptions()

    custom = object()
    one.media_handlers[falcon.MEDIA_JSON] = custom

    # the customizing parser sees its own replacement ...
    assert one.media_handlers[falcon.MEDIA_JSON] is custom
    assert len(one.media_handlers) == 2

    # ... and the other parser is completely unaffected
    assert falcon.MEDIA_JSON in two.media_handlers
    assert two.media_handlers[falcon.MEDIA_JSON] is not custom
    assert isinstance(two.media_handlers[falcon.MEDIA_JSON], JSONHandler)
    assert len(two.media_handlers) == 2