#!/usr/bin/env python3
"""Probe for bracket-bridge: reads req.remote_addr when scope['client'] is None.

Prints what the checked-out falcon does. On the buggy build, unpacking the
null client field raises TypeError and the probe exits non-zero; on a fixed
build it prints the documented fallback '127.0.0.1'.
"""
import asyncio

from falcon import testing
from falcon.asgi import Request


async def main() -> None:
    scope = testing.create_scope()
    scope['client'] = None
    req = Request(scope, None)
    print('remote_addr:', req.remote_addr)
    print('access_route:', req.access_route)


if __name__ == '__main__':
    asyncio.run(main())