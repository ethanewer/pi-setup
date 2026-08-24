import asyncio

class Managed:
    """An async resource whose cleanup (writing the marker) is guaranteed by
    __aexit__ to run on every exit path of an `async with` block."""
    def __init__(self, marker_path):
        self.marker_path = marker_path

    async def __aenter__(self):
        return self

    async def __aexit__(self, exc_type, exc, tb):
        # This runs whether or not the body raised; cleanliness guaranteed.
        with open(self.marker_path, 'w') as f:
            f.write('cleaned')
        return False  # do NOT suppress any exception