# ballast-berm: Mbed-TLS/mbedtls PSA CCM*-no-tag decrypt rejects messages
# shorter than one AES block (upstream issue #9314).
#
# The image clones Mbed-TLS/mbedtls SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree), extracts the project's own
# regression test for the bug from the FIX commit at build time into
# /opt/golden/, and overlays that fixed test data into the tree exactly as
# the mining reproduction did (`git checkout <fix> -- tests/suites/...`), so
# `make -C tests test_suite_psa_crypto && ./tests/test_suite_psa_crypto`
# fails inside the image with the mined symptom (1947 of 1949 passing, the
# two CCM*-no-tag short-message decrypt cases failing). The fix commit is
# fetched only into a throwaway bare clone that is deleted, so it is never
# reachable from /app/src. Neither mbedtls nor its framework submodule is a
# Terminal-Bench 2.1 source repository (checked against
# specs/tb21_source_repositories.json; the only submodule is
# github.com/Mbed-TLS/mbedtls-framework, which is not on that list).
#
# The library and the psa_crypto test suite are pre-built as cached image
# layers, so the agent's fix cycle is an incremental recompile of one file.
# Being two cache layers, the prebuilds also fail the image build if
# the mined failing state is not present.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

ARG UPSTREAM_SHA=dd48f0f23f8b5189031d6f3ac519b2b6113bd9e7
ARG FIX_SHA=7b6ddfcd25d95a1c6a452158db9205a6372b4426

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends build-essential make git \
            ca-certificates \
 && rm -rf /var/lib/apt/lists/*

# The build regenerates PSA driver wrappers with a Python script that
# imports jsonschema and jinja2. PEP 668 is bypassed with the same flag the
# rest of the suite uses; both pinned to versions verified on this base.
RUN pip3 install --break-system-packages --no-cache-dir jsonschema==4.26.0 jinja2==3.1.6

# --- a known uid for the tree owner ------------------------------------------
# Everything under /app is created by uid 1000 (the base image's `ubuntu` user,
# the same uid a non-root trial runs as), so the shell and make can rewrite it
# without any post-build chown/chmod. The image's default USER stays root
# (below) so harbor can write /logs; 1000 is just the owner of the deliverable
# tree, reachable by both a root and a uid-1000 agent.
RUN mkdir -p /app /opt/golden \
 && chown 1000:1000 /app /opt/golden

# ---- working clone: buggy parent commit, fix commit unreachable -------------
USER 1000:1000
RUN git clone --depth 1 https://github.com/Mbed-TLS/mbedtls.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin dd48f0f23f8b5189031d6f3ac519b2b6113bd9e7 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git submodule update --init framework

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/Mbed-TLS/mbedtls.git \
 && git fetch --depth 1 origin 7b6ddfcd25d95a1c6a452158db9205a6372b4426 \
 && mkdir -p /opt/golden \
 && git show 7b6ddfcd25d95a1c6a452158db9205a6372b4426:tests/suites/test_suite_psa_crypto.data \
      > /opt/golden/test_suite_psa_crypto.data \
 && test "$(sha256sum /opt/golden/test_suite_psa_crypto.data | cut -d' ' -f1)" \
      = "a22413025ce88aa659c901235b3fe6a8d67193601c927dcca211795545a4e72a" \
 && grep -q "PSA symmetric decrypt: CCM\*-no-tag, NIST DVPT AES-128 #15, 0 bytes" \
      /opt/golden/test_suite_psa_crypto.data \
 && cd / && rm -rf /tmp/fixsrc

# ---- overlay the corrected regression data into the working tree -------------
RUN cp /opt/golden/test_suite_psa_crypto.data /app/src/tests/suites/test_suite_psa_crypto.data

# ---- pre-build the library and the psa_crypto suite (cached layers) ----------
# Everything the trial needs is compiled here so the agent's edit-to-test
# cycle is one incremental recompile; the smoke run proves the mined failing
# state (1947/1949) is what the image ships.
RUN cd /app/src && make -j"$(nproc)" lib
RUN cd /app/src && make -C tests -j"$(nproc)" test_suite_psa_crypto
RUN cd /app/src && ./tests/test_suite_psa_crypto > /tmp/smoke.log 2>&1; \
    grep -qF "FAILED (1947 / 1949 tests (309 skipped))" /tmp/smoke.log

WORKDIR /app

USER root

CMD ["/bin/bash"]