# cistern-cable: encode/httpx emits a spurious trailing '' when iterating the
# decoded text of a streamed response body.
#
# The image clones encode/httpx SHALLOW at the PARENT commit (the real upstream
# bug is present in the working tree) and extracts the project's own regression
# test for the bug from the FIX commit at build time into /opt/golden/
# (upstream bytes never enter this repository). The fix commit is a descendant
# of the parent, so it is NOT reachable from the depth-1 clone the agent works
# on; the extraction uses a throwaway bare clone that is deleted. Pure-Python
# install; the reproduction is in-memory (no server, no network).
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=90538a3b4610ba49ce16c997bcfdb9101f9503be
ARG FIX_SHA=1e110964736a95d822144390b99d7ecf17fca527

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/encode/httpx.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 90538a3b4610ba49ce16c997bcfdb9101f9503be \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN mkdir -p /opt/golden \
 && git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/encode/httpx.git \
 && git fetch --depth 1 origin 1e110964736a95d822144390b99d7ecf17fca527 \
 && git show 1e110964736a95d822144390b99d7ecf17fca527:tests/test_decoders.py \
      > /opt/golden/test_decoders.py \
 && test -s /opt/golden/test_decoders.py \
 && grep -q "def test_streaming_text_decoder" /opt/golden/test_decoders.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- install (warm every cache at build time; trial is offline) ------------
# httpcore/anyio/etc. come from the project's own dependency metadata. The
# remaining packages are pinned exactly: chardet is required because
# tests/test_decoders.py imports it at module scope; the rest mirror the
# project's own requirements.txt so the project's test runner works as CI does.
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    ANYIO_BACKEND=asyncio

RUN cd /app/src \
 && python3 -m pip install -e '.[brotli,cli,http2,socks]' \
      chardet==5.2.0 \
      pytest==7.4.3 \
      trio==0.22.2 \
      trustme==1.1.0 \
      uvicorn==0.24.0.post1 \
      cryptography==41.0.7

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]