# ---------------------------------------------------------------------------
# luff-yard: WWWAuthenticate.to_header emits a trailing space for a
# parameterless challenge ("Bearer " instead of "Bearer").
#
# The image clones pallets/werkzeug and checks out upstream PARENT commit
# 795f4eaf6ef1fdc2fd1d7114c61ad384ede4322c (immediately before upstream commit
# 051fd66352cf8b3f0797249858068dedaead6d39 fixed issue #3127), so the agent
# gets the real repository with the real bug still in it.
#
# The working clone is created with `git init` + a single `git fetch --depth 1
# origin <parent-sha>` and detached there, so the ONLY commit object in the
# /app/src object store is the parent itself. Neither the fix commit nor any
# later history is reachable from /app/src. The golden test is extracted from
# the fix commit through a SEPARATE throwaway clone under /tmp which is
# rm -rf'd afterwards, so the fix bytes never enter the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=795f4eaf6ef1fdc2fd1d7114c61ad384ede4322c
ARG FIX_SHA=051fd66352cf8b3f0797249858068dedaead6d39

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/pallets/werkzeug.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# file lives only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/pallets/werkzeug.git /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git show ${FIX_SHA}:tests/test_http.py > /opt/golden/test_http.py \
 && test -s /opt/golden/test_http.py \
 && test "$(sha256sum /opt/golden/test_http.py | cut -d' ' -f1)" = \
       "c0c6cb1f0074b921cc2765b5d2e15d716ff9966890fcb719e64b0749be92a932" \
 && cd / && rm -rf /tmp/fixsrc \
 && chmod a+r /opt/golden/test_http.py

# ---- runtime and test environment, fully pinned (the trial has no network) --
# tests/conftest.py imports ephemeral-port-reserve at module import time, so it
# is needed for ANY collection of the project's own suite. pytest-xprocess is
# pinned per the mining record's dependency pins. cffi/cryptography/watchdog
# are the project's declared test extra; flit_core is the build backend for the
# legacy editable install.
RUN pip install --no-cache-dir \
        pytest==9.1.1 \
        pytest-timeout==2.4.0 \
        pytest-xprocess==1.0.2 \
        cffi==2.1.1 \
        cryptography==50.0.1 \
        ephemeral-port-reserve==1.1.4 \
        watchdog==6.0.0 \
        flit_core==4.0.2 \
 && cd /app/src \
 && pip install --no-cache-dir -e . --no-build-isolation \
 && chmod -R a+rwX /app

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

COPY files/ /app/

CMD ["/bin/bash"]