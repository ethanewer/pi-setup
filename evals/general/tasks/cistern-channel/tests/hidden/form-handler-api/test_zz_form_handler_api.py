"""Hidden case 3: the del operator through the public handler API.

The upstream regression test uses pop() on a bare MultipartParseOptions.
This case uses del on the parse_options of real MultipartFormHandler
instances -- the object real applications reach through the documented
`MultipartFormHandler.parse_options` attribute -- and exercises
Handlers.__delitem__ as the mutation path.
"""
import falcon
from falcon.media import MultipartFormHandler


def test_del_through_form_handler_api_is_isolated():
    h1 = MultipartFormHandler()
    h2 = MultipartFormHandler()

    del h1.parse_options.media_handlers[falcon.MEDIA_JSON]

    assert falcon.MEDIA_JSON not in h1.parse_options.media_handlers
    assert len(h1.parse_options.media_handlers) == 1

    assert falcon.MEDIA_JSON in h2.parse_options.media_handlers
    assert len(h2.parse_options.media_handlers) == 2
    assert (
        h1.parse_options.media_handlers
        is not h2.parse_options.media_handlers
    )