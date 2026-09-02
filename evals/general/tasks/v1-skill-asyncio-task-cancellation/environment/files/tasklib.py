import asyncio

async def long_task(tag, markers):
    """Run forever until cancelled; record the cancellation in markers[tag]."""
    try:
        while True:
            await asyncio.sleep(0.05)
    except asyncio.CancelledError:
        markers[tag] = True
        await asyncio.sleep(0)
        raise