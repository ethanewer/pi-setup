FROM bench-base:python-3.12


# Single-CPU deterministic environment; cpus = 1 in task.toml.
ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1 \
    PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1

# Runtime + toolchain + test dependencies, pinned exactly to the versions the
# mining run verified (requests deps) plus the local-test-server stack. The
# httpbin/werkzeug/flask wheels are needed ONLY by the test server that the
# upstream regression test runs against on 127.0.0.1; nothing here is a VCS
# fetch and nothing is fetched or vendored.
RUN python3 -m pip install --no-cache-dir \
        urllib3==2.7.0 certifi==2026.7.22 charset_normalizer==3.5.1 idna==3.19 PySocks==1.7.1 \
        setuptools==84.0.0 wheel==0.48.0 \
        pytest==9.1.1 pytest-httpbin==2.1.0 httpbin==0.10.2 \
        flask==3.1.3 werkzeug==3.1.4 decorator==5.2.1 itsdangerous==2.2.0 markupsafe==3.0.2

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Check out the REAL upstream repository at exactly the parent commit, with
# the shallowest possible history: the depth-1 tag checkout below pins the SHA
# so the object store in /app/src holds ONLY the parent commit. The fix
# commit (which the agent must not be able to look up or fetch) is never
# fetched into this checkout, and the build fails closed if upstream moves.
RUN git clone --depth 1 --branch v2.34.0 https://github.com/psf/requests.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "0b401c76b6e80a4eecf3c690085b2553f6e261ca" \
 && python3 -m pip install --no-cache-dir --no-deps --no-build-isolation -e /app/src \
 && chown -R 1000:1000 /app/src

# Pristine copy of the PARENT source for the verifier's pre-fix run. Built by
# archiving the parent commit's own objects (already the only objects in
# /app/src); the fix commit never exists anywhere in this image.
RUN mkdir -p /opt/presolve \
 && git -C /app/src archive 0b401c76b6e80a4eecf3c690085b2553f6e261ca src | tar -x -C /opt/presolve \
 && test -f /opt/presolve/src/requests/models.py

# Extract the project's own regression test (tests/test_requests.py exactly as
# it exists at the FIX commit, i.e. the parent's file plus the added
# `test_getattr_proxy_stream_follows_redirect` test) into /opt/golden using a
# THROWAWAY checkout that is deleted immediately afterwards, so upstream test
# bytes never land in this task tree and the fix commit never lands in /app/src.
RUN git init -q /tmp/upstream-fix-checkout && cd /tmp/upstream-fix-checkout \
 && git remote add origin https://github.com/psf/requests.git \
 && git fetch --depth 1 origin 6404f345e562d962abe6700a1c357ec1e7e18232 \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "6404f345e562d962abe6700a1c357ec1e7e18232" \
 && mkdir -p /opt/golden \
 && git show 6404f345e562d962abe6700a1c357ec1e7e18232:tests/test_requests.py > /opt/golden/test_requests.py \
 && test -s /opt/golden/test_requests.py \
 && grep -q "def test_getattr_proxy_stream_follows_redirect" /opt/golden/test_requests.py \
 && cd / \
 && rm -rf /tmp/upstream-fix-checkout

# Belt: prove the fix commit is not reachable from the trial checkout (the
# agent must not be able to read the answer with `git log --all`, even with no
# network: it must not exist as an object at all).
RUN cd /app/src \
 && if git cat-file -e 6404f345e562d962abe6700a1c357ec1e7e18232^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "0b401c76b6e80a4eecf3c690085b2553f6e261ca" \
 && test "$(git rev-list HEAD --count)" = "1" \
 && test "$(git fsck --no-reflogs --unreachable 2>/dev/null | wc -l)" = "0"

# Build-time gate: the upstream golden test must FAIL against a pristine
# parent tree (checked in a scratch copy that is deleted; the shipped tree
# stays untouched) and must show the real failure signature.
RUN cp -a /app/src /tmp/goldencheck && cp /opt/golden/test_requests.py /tmp/goldencheck/tests/test_requests.py \
 && cd /tmp/goldencheck && PYTHONPATH=/tmp/goldencheck/src python3 -m pytest -q \
      'tests/test_requests.py::TestRequests::test_getattr_proxy_stream_follows_redirect' \
      -p no:cacheprovider > /tmp/golden_parent.log 2>&1; rc=$?; \
    rm -rf /tmp/goldencheck; \
    if [ $rc -eq 0 ]; then \
      echo "ERROR: golden test passed at the parent commit (unexpected)"; cat /tmp/golden_parent.log >&2; exit 1; \
    fi; \
    grep -q "is not iterable" /tmp/golden_parent.log

WORKDIR /app

COPY files/ /app/

CMD ["/bin/bash"]