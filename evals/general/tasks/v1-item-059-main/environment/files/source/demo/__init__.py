# Demo package — do not modify the package source. Build it, serve it, install it.

__version__ = "1.0.0"


def greet(name: str = "world") -> str:
    """Return a friendly greeting."""
    return f"Hello, {name}!"