# capstan-drift: Mbed-TLS PKCS#7 object-reuse double-free task.
#
# The trial clone is the REAL upstream repository at the PARENT commit
# 5ca2218a2 (the bug is present). The FIX commit 67e696b43 is fetched only
# into a throwaway clone to extract the project's own regression test into
# /opt/golden, and is asserted to be unreachable from the trial clone.
# Submodule pins: framework e92a81996; tf-psa-crypto 93fa04691 (which itself
# pins framework e92a81996). Verified on 2026-09-12 against
# https://github.com/Mbed-TLS/mbedtls.git.
ARG UPSTREAM_SHA_PARENT=5ca2218a28a49cfdcc8cebe8953f6cb07bf7084f
ARG UPSTREAM_SHA_FIX=67e696b430716f95ed714f2c1404681697251438
ARG FRAMEWORK_SHA=e92a81996656d82941a9afce843453c57e1d51f5
ARG PSA_SHA=93fa04691f6d5628f51a369953856bf5bf75d31f

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX
ARG FRAMEWORK_SHA
ARG PSA_SHA

ENV OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 NUMEXPR_NUM_THREADS=1

# Build/runtime toolchain. Cmake is required (the 4.x tree is CMake-only);
# perl/python3-jsonschema/python3-jinja2 are used by the test-code generation
# and scripted build steps. No Python dependency pins apply (no pip install).
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential cmake perl python3 python3-jsonschema python3-jinja2 \
 && rm -rf /var/lib/apt/lists/*

# The trial may run as root or as uid 1000; make git safe for both and give
# the image a committer identity for any build-time commits.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the PARENT commit, shallow:
# `git init` + one depth-1 fetch of the pinned SHA means the object store in
# /app/src holds ONLY the parent commit. The fix commit — which an agent must
# not be able to look up or fetch — is never fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/Mbed-TLS/mbedtls.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Submodules, pinned by the gitlinks recorded in the parent commit:
#   framework        -> e92a81996656d82941a9afce843453c57e1d51f5
#   tf-psa-crypto    -> 93fa04691f6d5628f51a369953856bf5bf75d31f
#   tf-psa-crypto/framework -> e92a81996656d82941a9afce843453c57e1d51f5
# Both framework checkouts are mandatory: configure fails with
# 'framework/CMakeLists.txt not found' without them.
RUN cd /app/src \
 && git submodule update --init --depth 1 framework \
 && git submodule update --init --depth 1 tf-psa-crypto \
 && git -C tf-psa-crypto submodule update --init --depth 1 framework \
 && test "$(git -C framework rev-parse HEAD)" = "${FRAMEWORK_SHA}" \
 && test "$(git -C tf-psa-crypto rev-parse HEAD)" = "${PSA_SHA}" \
 && test "$(git -C tf-psa-crypto/framework rev-parse HEAD)" = "${FRAMEWORK_SHA}" \
 && echo "submodules pinned"

# Extract the project's own regression test for this bug (added by the fix
# commit to tests/suites/test_suite_pkcs7.{data,function}) into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so upstream
# test bytes never land in this task tree and the fix commit never lands in
# /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/Mbed-TLS/mbedtls.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_FIX}" \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:tests/suites/test_suite_pkcs7.data \
        > /opt/golden/test_suite_pkcs7.data \
 && git show ${UPSTREAM_SHA_FIX}:tests/suites/test_suite_pkcs7.function \
        > /opt/golden/test_suite_pkcs7.function \
 && test -s /opt/golden/test_suite_pkcs7.data \
 && test -s /opt/golden/test_suite_pkcs7.function \
 && grep -q "pkcs7_parse_reuse" /opt/golden/test_suite_pkcs7.function \
 && grep -q "reused object after multiple signers" /opt/golden/test_suite_pkcs7.data \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone, and the
# tree is exactly the pinned parent commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
        echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && echo "fix commit unreachable from trial clone"

# Warm build. Configure once and build the test targets the task needs (the
# library plus the pkcs7 and x509parse test binaries) so the agent's work is
# incremental on top of this layer; the trial has no network.
RUN cd /app/src \
 && cmake -B build -DENABLE_TESTING=ON . > /tmp/warm-configure.log 2>&1 \
 && cmake --build build --target test_suite_pkcs7 test_suite_x509parse -j8 \
        > /tmp/warm-build.log 2>&1 \
 && test -x build/tests/test_suite_pkcs7 \
 && test -x build/tests/test_suite_x509parse \
 && ./build/tests/test_suite_x509parse > /tmp/warm-x509.log 2>&1 \
 && grep -q "PASSED (888 / 888 tests (58 skipped))" /tmp/warm-x509.log \
 && echo "warm build + x509parse sanity OK"

# The image is built as root; the trial may run as root or as uid 1000
# (user 'ubuntu' exists in the base image). Make the whole tree writable by
# uid 1000 so an unprivileged trial can edit sources and the warm build/ dir.
RUN chown -R 1000:1000 /app/src 2>/dev/null || true \
 && chmod -R a+rwX /app/src

COPY files/ /app/
RUN chmod -R a+rwX /app

WORKDIR /app

CMD ["/bin/bash"]