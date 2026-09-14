ARG UPSTREAM_SHA=cd75c4ec10254f4c98964308a0a1437274c7be4f
ARG FIX_SHA=4c8f9944ead815e264bcb71cd5f0e8eeb2a75689

FROM bench-base:python-3.12

ARG UPSTREAM_SHA
ARG FIX_SHA

ENV PYTHONPYCACHEPREFIX=/tmp/pycache \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends git \
 && rm -rf /var/lib/apt/lists/* \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# The real upstream tree (python/mypy) at the buggy PARENT commit, pinned to
# the immutable 40-hex revision: the build fails closed if upstream moves.
# The FIX commit is NEVER fetched into this clone, so its objects are
# unreachable; that is asserted with git cat-file before the metadata is
# stripped. A pristine sibling copy is kept (root-owned, read-only) for the
# verifier's pre-fix half. All git metadata is then removed from both copies.
# Ownership lands on uid 1000 in the SAME RUN so no chown layer is added.
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/python/mypy.git \
 && git -C /app/src fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && if git -C /app/src cat-file -e "$FIX_SHA^{commit}" >/dev/null 2>&1; then \
      echo "ERROR: fix object $FIX_SHA is reachable in the agent clone" >&2; exit 1; \
    fi \
 && cp -a /app/src /opt/pristine-src \
 && rm -rf /app/src/.git /opt/pristine-src/.git \
 && chown -R 1000:1000 /app \
 && chmod -R u+rwX,go+rX /app/src \
 && chown -R 0:0 /opt/pristine-src \
 && chmod -R a-w /opt/pristine-src \
 && chmod -R a+rX /opt/pristine-src \
 && echo "checked out upstream parent $UPSTREAM_SHA; fix object $FIX_SHA absent"

# The project's own regression tests for this defect, extracted verbatim from
# the FIX commit through a SEPARATE throwaway clone under /tmp (deleted right
# after), so the fix commit never enters the repository the agent receives.
# check-classes.test carries the new regression case; check-python310.test and
# check-python312.test carry the fix's updated/added cases (the match-arm
# reveal and the PEP 695 'type[T]' case). /opt/golden lives in the image only.
RUN mkdir -p /opt/golden /tmp/goldclone \
 && git init -q /tmp/goldclone \
 && git -C /tmp/goldclone remote add origin https://github.com/python/mypy.git \
 && git -C /tmp/goldclone fetch --depth 1 origin "$FIX_SHA" \
 && git -C /tmp/goldclone checkout -q --detach FETCH_HEAD \
 && test "$(git -C /tmp/goldclone rev-parse HEAD)" = "$FIX_SHA" \
 && git -C /tmp/goldclone show "$FIX_SHA:test-data/unit/check-classes.test" > /opt/golden/check-classes.test \
 && git -C /tmp/goldclone show "$FIX_SHA:test-data/unit/check-python310.test" > /opt/golden/check-python310.test \
 && git -C /tmp/goldclone show "$FIX_SHA:test-data/unit/check-python312.test" > /opt/golden/check-python312.test \
 && chmod 444 /opt/golden/check-classes.test /opt/golden/check-python310.test /opt/golden/check-python312.test \
 && chmod 755 /opt/golden \
 && rm -rf /tmp/goldclone \
 && echo "golden regression tests extracted from fix commit $FIX_SHA"

# Runtime and test dependencies, pinned exactly (versions from the project's
# own test-requirements.txt at the pinned revision).
RUN pip install --no-cache-dir \
      typing_extensions==4.15.0 \
      mypy_extensions==1.1.0 \
      pathspec==1.1.1 \
      librt==0.11.0 \
      ast-serialize==0.5.0 \
      pytest==9.0.3 \
      pytest-xdist==3.8.0 \
      lxml==6.1.0 \
      attrs==26.1.0 \
      psutil==7.2.2 \
      pygments==2.20.0

WORKDIR /app

COPY --chown=1000:1000 files/ /app/