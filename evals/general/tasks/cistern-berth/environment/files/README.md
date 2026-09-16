# cistern-berth environment notes

This image contains a real, SHA-pinned source checkout of Python's `aiohttp`
web framework at `/app/src`, editable-installed in pure-Python mode
(`AIOHTTP_NO_EXTENSIONS=1`), so a change under `/app/src/aiohttp/` is
immediately live in `import aiohttp`.

Installed test toolchain (all pinned): pytest 9.1.1, pytest-asyncio 1.4.0,
pytest-aiohttp 1.1.1, pytest-timeout 2.4.0, freezegun 1.5.5, coverage 7.15.4.

The container has no network access during the trial. Everything needed is
on disk; do not try to install or download anything.