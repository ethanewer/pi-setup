ARG UPSTREAM_SHA_PARENT=d1615b814af7136595927ec98d20f5f873a9f729
ARG UPSTREAM_SHA_FIX=6bba0a8355db632f7287905ec577483979c47905

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Build toolchain from the mining recipe: plain apt on the ubuntu base.
# Plain http to archive.ubuntu.com is blocked on this host, so rewrite the
# apt sources to https first (the recipe's step 1).
RUN sed -i 's|http://|https://|g' /etc/apt/sources.list.d/ubuntu.sources \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential perl python3 python3-jsonschema python3-jinja2 git \
 && rm -rf /var/lib/apt/lists/* \
 && git config --global --add safe.directory '*'

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store in /app/src holds only the parent commit. The
# fix commit (which an agent must not be able to look up or fetch) is never
# fetched into this clone. HEAD is asserted against the pinned SHA so the
# build fails closed if upstream moves. The framework submodule is checked
# out at the gitlink recorded in the parent commit (750634d3...).
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/Mbed-TLS/mbedtls.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && git submodule update --init framework \
 && chown -R 1000:1000 /app/src

# The two upstream regression case blocks for this bug (the exact added
# lines of the parent->fix diff of tests/suites/test_suite_psa_crypto_util.data)
# live in the TASK TREE at tests/golden/golden_cases.data, which harbor mounts
# at /tests ONLY for the verifier — deliberately not baked into this image:
# an agent inside the container has no access to a ready-made reproduction.
# The fix commit is NEVER fetched into /app/src; the golden lines were
# extracted through a SEPARATE throwaway clone during authoring.

# Belt: prove the fix commit is NOT reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# Record verify-time trust anchors: the toolchain the verifier will build
# with, pinned byte-for-byte so a modified container (stub make/gcc or a
# tampered file) is detected before any verifier build runs.
RUN sha256sum /usr/bin/make /usr/bin/gcc /usr/bin/cc /usr/bin/python3 /usr/bin/git > /opt/pins.sha256

# The trial may run as uid 1000 (user `ubuntu` in the base image); make the
# whole clone writable by that user and WARM every build cache AS that user:
# the library plus the three suites the task uses are compiled at image
# build time at the parent commit, so the agent's and verifier's incremental
# rebuilds (one source file + test data) take seconds even with cpus=1.
WORKDIR /app
# The chown to uid 1000 happens in the clone RUN above, in the same layer that
# created the tree. It used to be a RUN of its own here, which copied the entire
# clone into a second layer for nothing but a metadata change. Ownership is all
# the warm builds below need: they run AS uid 1000 and uid 1000 owns the tree.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && make -j1 lib > /tmp/warm-lib.log 2>&1'; rc=$?; \
    tail -4 /tmp/warm-lib.log; \
    if [ $rc -ne 0 ]; then echo "WARM LIB BUILD FAILED (exit $rc)"; exit $rc; fi
RUN su -s /bin/bash ubuntu -c 'cd /app/src && make -C tests test_suite_psa_crypto_util test_suite_psa_crypto test_suite_pk > /tmp/warm-suite.log 2>&1'; rc=$?; \
    tail -4 /tmp/warm-suite.log; \
    if [ $rc -ne 0 ]; then echo "WARM SUITE BUILD FAILED (exit $rc)"; exit $rc; fi

# The pins and image are final; also prove parent-tree suites run green at
# this commit as a baseline sanity check (fail-closed: any non-zero suite
# exit aborts the build).
RUN cd /app/src \
 && ./tests/test_suite_psa_crypto_util > /tmp/base-util.log 2>&1 && tail -1 /tmp/base-util.log \
 && ./tests/test_suite_psa_crypto > /tmp/base-psa.log 2>&1 && tail -1 /tmp/base-psa.log \
 && ./tests/test_suite_pk > /tmp/base-pk.log 2>&1 && tail -1 /tmp/base-pk.log \
 && chmod -R a+rwX /app/src
RUN chmod 444 /opt/pins.sha256

COPY files/ /app/
# /app/src was made a+rwX in the same RUN that ran the baseline suites above, so
# it is deliberately not touched again here. A recursive chmod of /app would
# rewrite the whole compiled library and test-suite tree into a fresh
# copy-on-write layer to change nothing. Only /app itself and whatever the COPY
# just brought in still need the bit.
RUN chmod a+rwX /app \
 && find /app -mindepth 1 -maxdepth 1 ! -name src -exec chmod -R a+rwX {} +

CMD ["/bin/bash"]