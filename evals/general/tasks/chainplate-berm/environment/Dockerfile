# chainplate-berm: netty/netty zlib-decompressor tail-loss bugfix.
#
# Clones the REAL upstream repository at the pinned PARENT commit (the bug is
# live there), extracts the project's own regression test from the FIX commit
# into /opt/golden via a throwaway clone, warms a Maven local repository so the
# trial runs fully offline, and re-confirms BOTH directions inside this image:
# the upstream regression test must FAIL on the parent tree and PASS on the
# fixed tree.

ARG UPSTREAM_SHA_PARENT=87d2f7506cee4100d765be62c481dbd22c9501dc
ARG UPSTREAM_SHA_FIX=7681affcf120fca1de8554095216ddea20b408c5

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The whole trial is offline after build time; everything Maven could need
# lives in /opt/m2, populated by the warm build below. MAVEN_OPTS keeps the
# repository location and JVM heap constant for every invocation (mvn, su,
# root, uid 1000 alike). Commands opt into offline mode with -o explicitly.
ENV MAVEN_OPTS="-Xmx5g -Dmaven.repo.local=/opt/m2 -Dmaven.wagon.http.pool=false" \
    TZ=UTC

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends openjdk-21-jdk-headless maven git ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && java -version 2>&1 | head -1 \
 && mvn -version | head -3

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned SHA
# means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which the agent must not be able to look up or fetch) is never
# fetched into this clone.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/netty/netty.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression test for this bug (the test the fix
# commit appends to JdkZlibDecompressorTest.java) into /opt/golden, and the
# FIXED main source into /tmp (used only to re-confirm the fix direction),
# using a THROWAWAY clone that is deleted immediately afterwards, so upstream
# test bytes never land in this task tree and the fix commit never lands in
# /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/netty/netty.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibDecompressorTest.java > /opt/golden/JdkZlibDecompressorTest.java \
 && test -s /opt/golden/JdkZlibDecompressorTest.java \
 && grep -q "testHighlyCompressibleStreamIsFullyDecompressed" /opt/golden/JdkZlibDecompressorTest.java \
 && git show ${UPSTREAM_SHA_FIX}:codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecompressor.java > /tmp/JdkZlibDecompressor.fixed.java \
 && test -s /tmp/JdkZlibDecompressor.fixed.java \
 && grep -q "MIN_OUTPUT_BUFFER_SIZE" /tmp/JdkZlibDecompressor.fixed.java \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}"

# The image is built as root; the trial may run as root or as uid 1000 (user
# `ubuntu` already exists in the base image). Give uid 1000 ownership of the
# tree and of the shared Maven repository so every writable path is writable
# by uid 1000 from the start.
WORKDIR /app
RUN mkdir -p /opt/m2 && chmod -R a+rwX /opt/m2 \
 && chmod -R a+rwX /app/src && chown -R 1000:1000 /app/src 2>/dev/null || true

# WARM pass: the one-time reactor build of the module closure (common, buffer,
# transport, codec-base -- everything codec-compression depends on) downloads
# all dependencies from Maven Central into /opt/m2 and INSTALLS the
# 4.2.16.Final-SNAPSHOT module artifacts that the per-module test runs resolve
# against. The trial has no network, so this layer IS the warm cache.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && mvn -pl codec-base,codec-compression -am install -DskipTests -Dcheckstyle.skip=true -Dxml.format.skip=true > /tmp/warm-install.log 2>&1'; rc=$?; \
    tail -8 /tmp/warm-install.log; \
    if [ $rc -ne 0 ]; then echo "WARM INSTALL FAILED (exit $rc)"; exit $rc; fi; \
    ls /opt/m2/io/netty/ | head -8; \
    test -d /app/src/codec-compression/target/classes && echo "codec-compression main classes compiled"

# Direction 1 (parent): plant the upstream regression test and run it on the
# PARENT tree. It MUST FAIL here -- if it passes, this image does not
# reproduce the bug and the task cannot work. This run also warms the surefire
# plugin in /opt/m2 so the trial's test runs are fully offline.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    cp /opt/golden/JdkZlibDecompressorTest.java codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibDecompressorTest.java && \
    mvn -pl codec-compression test -Dtest=JdkZlibDecompressorTest -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true > /tmp/warm-golden-parent.log 2>&1'; rc=$?; \
    echo "=== parent-direction upstream regression run rc=$rc (expected non-zero) ==="; \
    tail -20 /tmp/warm-golden-parent.log; \
    if [ $rc -eq 0 ]; then echo "ERROR: regression test PASSED on the parent tree; bug does not reproduce here"; exit 1; fi; \
    grep -q "Compressed stream ended before the end-of-stream marker" /tmp/warm-golden-parent.log || { echo "ERROR: expected upstream failure message not found"; exit 1; }; \
    grep -qE "Errors: [1-9]" /tmp/warm-golden-parent.log || { echo "ERROR: expected a non-zero error count in the surefire summary"; exit 1; }

# Direction 2 (fix): overlay the fixed main source exactly as a solver would,
# run the same upstream regression test OFFLINE; it must PASS.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    cp /tmp/JdkZlibDecompressor.fixed.java codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecompressor.java && \
    grep -q "MIN_OUTPUT_BUFFER_SIZE" codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecompressor.java && \
    cp /opt/golden/JdkZlibDecompressorTest.java codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibDecompressorTest.java && \
    mvn -o -pl codec-compression test -Dtest=JdkZlibDecompressorTest -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true > /tmp/warm-golden-fix.log 2>&1'; rc=$?; \
    echo "=== fix-direction upstream regression run rc=$rc (expected 0) ==="; \
    tail -20 /tmp/warm-golden-fix.log; \
    if [ $rc -ne 0 ]; then echo "ERROR: regression test FAILED on the fixed tree"; exit 1; fi; \
    grep -qE "Tests run: [1-9][0-9]*, Failures: 0, Errors: 0" /tmp/warm-golden-fix.log \
      || { echo "ERROR: expected a green surefire summary in the fix-direction run"; exit 1; }

# Restore the pristine parent tree: the trial must start from EXACT parent
# bytes (no planted test, no applied fix), with a clean worktree and index.
# codec-compression/target is deleted too: the fix-direction warm run above
# compiled the FIXED class files into it, and shipping them would let an
# untouched (unfixed) tree pass the regression test, so the trial must
# recompile codec-compression from source.
# /tmp is scrubbed too: the fixed main source extracted for the fix
# direction and the warm-build logs must not ship in the image. Shipping the
# fixed source would hand the agent the ground-truth answer (a copy into
# codec-compression/.../JdkZlibDecompressor.java passes every check), and the
# logs name the failing method and line numbers the agent is supposed to find.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    git restore --worktree --source=HEAD -- codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecompressor.java codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibDecompressorTest.java && \
    rm -rf codec-compression/target && \
    test -z "$(git status --porcelain)" && \
    test "$(git rev-parse HEAD)" = "'"${UPSTREAM_SHA_PARENT}"'"' \
 && echo "tree restored to pristine parent bytes; codec-compression recompiles from source" \
 && cd /app/src && test ! -d codec-compression/target && echo "codec-compression/target removed" \
 && git -C /app/src rev-parse HEAD \
 && rm -f /tmp/JdkZlibDecompressor.fixed.java /tmp/JdkZlibDecompressor.java \
        /tmp/warm-install.log /tmp/warm-golden-parent.log /tmp/warm-golden-fix.log \
 && test ! -e /tmp/JdkZlibDecompressor.fixed.java \
 && echo "tree restored; codec-compression recompiles from source; /tmp scrubbed of fixed-source extract and warm logs"

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]