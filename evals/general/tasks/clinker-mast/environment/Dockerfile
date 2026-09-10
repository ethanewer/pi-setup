# clinker-mast: upstream-clone library-feature task on encode/httpx 0.28.1
#
# The upstream repository is cloned, SHA-pinned and editable-installed at
# build time (network exists while the image builds). The trial runs with no
# network, so everything the task needs is already in this image: the pinned
# checkout at /app/src, its editable install, and a pinned test toolchain.
#
# The agent's job is to implement a missing feature inside the /app/src
# checkout; /app/feature.md (created by the agent) documents it.

FROM bench-base:python-3.12

# Commit behind refs/tags/0.28.1 (a lightweight tag). Resolved by the author
# on 2026-08 via `git ls-remote https://github.com/encode/httpx.git
# refs/tags/0.28.1`. A tag can be force-moved upstream; the hash is the pin.
ARG UPSTREAM_SHA=26d48e0634e6ee9cdc0533996db289ce4b430177

# git-uid-1000 safety and build identity (agents may want to git commits).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Pinned test toolchain. Resolved against this base image's own interpreter.
RUN pip install --no-cache-dir pytest==8.4.1 pytest-asyncio==0.26.0 anyio==4.9.0 trio==0.31.0 uvicorn==0.35.0 trustme==1.2.0 cryptography==45.0.4 chardet==5.2.0 h2==4.2.0 brotli==1.2.0 zstandard==0.25.0

# Clone the upstream project at the pinned revision: shallow, fail closed if
# the hash ever drifts from the pin, then editable-install it so changes the
# agent makes under /app/src are live in `import httpx`.
RUN git clone --depth 1 --branch 0.28.1 https://github.com/encode/httpx.git /app/src \
    && cd /app/src \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
    && pip install --no-cache-dir -e .

# The relevant part of the upstream suite must be green on the pristine tree
# already (it is what the verifier also asserts after the agent's change).
RUN cd /app/src \
    && python3 -m pytest tests/test_exported_members.py tests/client/test_event_hooks.py tests/client/test_client.py -q -p no:cacheprovider

WORKDIR /app

# Thread-pool pins (the task is pure Python; these keep any extension libs
# single-threaded as the sweep is one CPU).
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 PYTHONDONTWRITEBYTECODE=1

COPY files/ /app/