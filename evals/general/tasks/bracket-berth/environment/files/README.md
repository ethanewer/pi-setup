# bracket-berth environment notes

This image contains a real, SHA-pinned source checkout of Python's `httpx`
HTTP library at `/app/src`, editable-installed (a change under `/app/src/httpx/`
is immediately live in `import httpx`).

Installed test toolchain (all pinned): pytest 8.4.1, pytest-asyncio 0.26.0,
anyio 4.9.0, trio 0.31.0, uvicorn 0.35.0, trustme 1.2.0, cryptography 45.0.4,
chardet 5.2.0, h2 4.2.0, brotli 1.2.0, zstandard 0.25.0.

The container has no network access during the trial. Everything needed is on
disk; do not try to install or download anything.