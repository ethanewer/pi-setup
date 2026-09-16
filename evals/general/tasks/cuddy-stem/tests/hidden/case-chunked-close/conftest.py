import asyncio
from collections.abc import Iterator

import pytest


@pytest.fixture()
def event_loop() -> Iterator[asyncio.AbstractEventLoop]:
    loop = asyncio.new_event_loop()
    try:
        yield loop
    finally:
        loop.close()