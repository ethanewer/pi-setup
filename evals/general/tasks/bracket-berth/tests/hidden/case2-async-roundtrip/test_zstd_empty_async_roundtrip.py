"""Hidden case 2: zero-length zstd responses through a real async client
round-trip, read via .aread() and .aiter_bytes() (the upstream regression
test never exercises the async reading paths)."""

import asyncio

import httpx


async def handler(request: httpx.Request) -> httpx.Response:
    return httpx.Response(200, headers={"Content-Encoding": "zstd"}, content=b"")


async def main() -> None:
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        first = await client.get("https://example.com/zero-length")
        assert await first.aread() == b""

        second = await client.get("https://example.com/iter")
        assert [chunk async for chunk in second.aiter_bytes()] == []

        third = await client.get("https://example.com/content")
        assert third.content == b""


def test_empty_zstd_via_async_client() -> None:
    asyncio.run(main())