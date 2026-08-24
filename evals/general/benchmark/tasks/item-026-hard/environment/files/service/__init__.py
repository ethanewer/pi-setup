__all__ = ['main', 'cookies', 'keys', 'transport', 'app']


def app():
    from .main import app as _app
    return _app