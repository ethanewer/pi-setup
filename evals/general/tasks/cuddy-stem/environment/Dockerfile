# cuddy-stem: aiohttp WebSocket reader accepts reserved close status 1006.
#
# The image clones aio-libs/aiohttp SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository).  The fix commit
# is a descendant of the parent, so it is NOT reachable from the depth-1
# clone the agent works on; the extraction uses a throwaway bare clone that
# is deleted immediately afterwards, so the fix object never enters /app/src.
#
# Pure-Python build: AIOHTTP_NO_EXTENSIONS=1 skips the Cython/llhttp compile.
# setup.py insists on vendor/llhttp being present, so the submodule is
# fetched shallow and pinned by its upstream URL (nodejs/llhttp).
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=14a1b5427213b5b982922627a44e4c5ae23bc0e3
ARG FIX_SHA=20acdf440b0a39c00054d4a70ea59376b793c83d

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working checkout: buggy parent commit, fix commit unreachable ----------
# A depth-1 clone of the default branch cannot contain the parent SHA, so
# fetch the parent by SHA, detach onto it and fail closed if upstream moves.
RUN git clone --depth 1 https://github.com/aio-libs/aiohttp.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 14a1b5427213b5b982922627a44e4c5ae23bc0e3 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git submodule update --init --depth 1 \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/aio-libs/aiohttp.git \
 && git fetch --depth 1 origin 20acdf440b0a39c00054d4a70ea59376b793c83d \
 && mkdir -p /opt/golden \
 && git show 20acdf440b0a39c00054d4a70ea59376b793c83d:tests/test_websocket_parser.py \
      > /opt/golden/test_websocket_parser.py \
 && test -s /opt/golden/test_websocket_parser.py \
 && grep -q "test_close_frame_reserved_code" /opt/golden/test_websocket_parser.py \
 && chmod 444 /opt/golden/test_websocket_parser.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial has no network) ---------
ENV AIOHTTP_NO_EXTENSIONS=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN cd /app/src \
 && pip install -e . \
 && pip install pytest==9.1.1 pytest-asyncio==1.4.0 pytest-aiohttp==1.1.1 \
            pytest-timeout==2.4.0 freezegun==1.5.5 coverage==7.16.0

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]