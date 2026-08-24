# Demo package — initially at version 1.0.0. Build, version-bump, serve, install.

__version__ = "1.0.0"


def greet(name: str = "world") -> str:
    """Return a friendly greeting."""
    return f"Hello, {name}!"