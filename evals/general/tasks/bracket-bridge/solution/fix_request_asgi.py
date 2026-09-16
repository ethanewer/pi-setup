#!/usr/bin/env python3
"""Apply the upstream fix for the null-client ASGI crash to /app/src.

The ASGI access_route cache in falcon/asgi/request.py unpacks the connection
scope's 'client' field and only catches KeyError. When a server sets the
client field to None (uvicorn on a Unix socket and similar), the unpack
raises TypeError. The upstream fix widens the except clause so the None case
falls back to the documented '127.0.0.1' default exactly like a missing
field.

This script performs a single, assertion-guarded edit to
falcon/asgi/request.py and only touches that one location.
"""
import pathlib
import sys

SRC = pathlib.Path('/app/src/falcon/asgi/request.py')

OLD = """                client, __ = self.scope['client']
            except KeyError:
"""
NEW = """                client, __ = self.scope['client']
            except (KeyError, TypeError):
"""


def main() -> int:
    src = SRC.read_text(encoding='utf-8')
    count = src.count(OLD)
    if count != 1:
        print(f'pattern found {count} times in {SRC}, expected 1; aborting', file=sys.stderr)
        return 1
    SRC.write_text(src.replace(OLD, NEW), encoding='utf-8')
    print('patched falcon/asgi/request.py: except KeyError -> except (KeyError, TypeError)')
    return 0


if __name__ == '__main__':
    sys.exit(main())