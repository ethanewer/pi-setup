"""Token normalization helpers (intermediate transform, not the boundary)."""

GUEST = 'guest'


def normalize(token):
    return (token or GUEST).strip()