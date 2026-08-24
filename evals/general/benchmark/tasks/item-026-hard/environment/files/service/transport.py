"""Transport layer: composes user data into the cookie payload (intermediate)."""


def compose(token, ttl):
    return "uid=%s&ttl=%s" % (token, ttl)