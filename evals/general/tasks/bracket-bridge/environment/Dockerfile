# bracket-bridge: falcon ASGI RemoteAddr crashes when scope['client'] is None.
#
# The image clones falconry/falcon SHALLOW at the PARENT commit (the real
# upstream bug #2583 is present in the working tree) and extracts the project's
# own regression test for the bug from the FIX commit at build time into
# /opt/golden/ (upstream bytes never enter this repository). The fix commit is
# a descendant of the parent, but it is never fetched into the working clone,
# so it is unreachable from /app/src; the golden extraction uses a throwaway
# bare clone that is deleted afterwards.
#
# Pure-Python build: FALCON_DISABLE_CYTHON=1 skips the Cython compile, so the
# editable install is fast and the imported code is exactly the checked-out
# (buggy) tree.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=bc01a2b0a62415a562430fe590a798c1042ab3f5
ARG FIX_SHA=a54317c7f8ec51a7fec8ce83df6b9f4852113253

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit, fix commit unreachable ------------
# A depth-1 clone of master cannot contain the parent SHA, so fetch the parent
# by SHA, detach onto it and fail closed if upstream ever moves.
RUN git clone --depth 1 https://github.com/falconry/falcon.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin bc01a2b0a62415a562430fe590a798c1042ab3f5 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit --------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/falconry/falcon.git \
 && git fetch --depth 1 origin a54317c7f8ec51a7fec8ce83df6b9f4852113253 \
 && mkdir -p /opt/golden \
 && git show a54317c7f8ec51a7fec8ce83df6b9f4852113253:tests/asgi/test_request_asgi.py \
      > /opt/golden/test_request_asgi.py \
 && test -s /opt/golden/test_request_asgi.py \
 && grep -q "test_client_none_in_scope" /opt/golden/test_request_asgi.py \
 && cd / && rm -rf /tmp/fixsrc

# ---- isolated source-fidelity probe (baked into the image; see tests/test.sh) --
# Runs with `python3 -S` + PYTHONPATH=/app/src so no site-packages import hook
# can affect it: the verdict is taken from the checked-out source itself.
COPY files/probe_isolated.py /opt/golden/probe_isolated.py
RUN test -s /opt/golden/probe_isolated.py && chmod 444 /opt/golden/probe_isolated.py && chown root:root /opt/golden/*

# ---- install (warm every cache at build time; trial is offline) ------------
ENV FALCON_DISABLE_CYTHON=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

RUN cd /app/src \
 && pip install -e . \
 && pip install pytest==9.1.1

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]