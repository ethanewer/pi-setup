# ballast-mooring: netty/netty HTTP-date substring-parse bugfix.
#
# Clones the REAL upstream repository at the pinned PARENT commit (the bug is
# live there), extracts the project's own regression test from the FIX commit
# into /opt/golden via a throwaway clone, warms a Maven local repository so the
# trial runs fully offline, and re-confirms BOTH directions inside this image:
# the upstream regression test must FAIL on the parent tree and PASS on the
# fixed tree.

ARG UPSTREAM_SHA_PARENT=ba8e9e64f89fc91b5085cd8bc21bd9ef83264ba1
ARG UPSTREAM_SHA_FIX=692d23f9899c34e9fed537e28ba940bfc952a763

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# The whole trial is offline after build time; everything Maven could need
# lives in /opt/m2, populated by the warm build below. MAVEN_OPTS keeps the
# repository location and JVM heap constant for every invocation (mvn, su,
# root, uid 1000 alike). Commands opt into offline mode with -o explicitly.
# TZ=UTC makes java.util.Date.toString() deterministic in the reproduction.
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
# commit appends to codec-base/.../DateFormatterTest.java) into /opt/golden
# using a THROWAWAY clone that is deleted immediately afterwards, so upstream
# test bytes never land in this task tree and the fix commit never lands in
# /app/src.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/netty/netty.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:codec-base/src/test/java/io/netty/handler/codec/DateFormatterTest.java > /opt/golden/DateFormatterTest.java \
 && test -s /opt/golden/DateFormatterTest.java \
 && grep -q "testParseHttpDateSubstringDoesNotOverrunEnd" /opt/golden/DateFormatterTest.java \
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
# transport, codec-base, codec-compression -- everything codec-base depends on)
# downloads all dependencies from Maven Central into /opt/m2 and INSTALLS the
# 4.2.16.Final-SNAPSHOT module artifacts that the per-module test runs resolve
# against. The trial has no network, so this layer IS the warm cache.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && mvn -pl codec-base,codec-compression -am install -DskipTests -Dcheckstyle.skip=true -Dxml.format.skip=true > /tmp/warm-install.log 2>&1'; rc=$?; \
    tail -8 /tmp/warm-install.log; \
    if [ $rc -ne 0 ]; then echo "WARM INSTALL FAILED (exit $rc)"; exit $rc; fi; \
    ls /opt/m2/io/netty/ | head -8; \
    test -d /app/src/codec-base/target/classes && echo "codec-base main classes compiled"

# Direction 1 (parent): plant the upstream regression test and run it on the
# PARENT tree. It MUST FAIL here -- if it passes, this image does not
# reproduce the bug and the task cannot work. This run also warms the surefire
# plugin in /opt/m2 so the trial's test runs are fully offline.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    cp /opt/golden/DateFormatterTest.java codec-base/src/test/java/io/netty/handler/codec/DateFormatterTest.java && \
    mvn -pl codec-base test -Dtest=DateFormatterTest -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true > /tmp/warm-golden-parent.log 2>&1'; rc=$?; \
    echo "=== parent-direction upstream regression run rc=$rc (expected non-zero) ==="; \
    tail -20 /tmp/warm-golden-parent.log; \
    if [ $rc -eq 0 ]; then echo "ERROR: regression test PASSED on the parent tree; bug does not reproduce here"; exit 1; fi; \
    grep -q "expected: <Sun Nov 06 08:49:37 UTC 1994> but was: <null>" /tmp/warm-golden-parent.log \
      || { echo "ERROR: expected upstream failure message not found"; exit 1; }

# Direction 2 (fix): apply the one-line fix exactly as a solver would, run the
# same upstream regression test OFFLINE; it must PASS.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    sed -i "s/return tokenStart != -1 \&\& parseToken(txt, tokenStart, txt.length());/return tokenStart != -1 \&\& parseToken(txt, tokenStart, end);/" codec-base/src/main/java/io/netty/handler/codec/DateFormatter.java && \
    grep -q "parseToken(txt, tokenStart, end);" codec-base/src/main/java/io/netty/handler/codec/DateFormatter.java && \
    cp /opt/golden/DateFormatterTest.java codec-base/src/test/java/io/netty/handler/codec/DateFormatterTest.java && \
    mvn -o -pl codec-base test -Dtest=DateFormatterTest -Dsurefire.failIfNoSpecifiedTests=false -Dcheckstyle.skip=true > /tmp/warm-golden-fix.log 2>&1'; rc=$?; \
    echo "=== fix-direction upstream regression run rc=$rc (expected 0) ==="; \
    tail -20 /tmp/warm-golden-fix.log; \
    if [ $rc -ne 0 ]; then echo "ERROR: regression test FAILED on the fixed tree"; exit 1; fi; \
    grep -q "Tests run: 14, Failures: 0" /tmp/warm-golden-fix.log \
      || { echo "ERROR: expected 14/14 green in the fix-direction run"; exit 1; }

# Restore the pristine parent tree: the trial must start from EXACT parent
# bytes (no planted test, no applied fix), with a clean worktree and index.
# codec-base/target is deleted too: the fix-direction warm run above compiled
# the FIXED class files into it, and shipping them would let an untouched
# (unfixed) tree pass the regression test, so the trial must recompile
# codec-base from source.
RUN su -s /bin/bash ubuntu -c 'cd /app/src && \
    git restore --worktree --source=HEAD -- codec-base/src/main/java/io/netty/handler/codec/DateFormatter.java codec-base/src/test/java/io/netty/handler/codec/DateFormatterTest.java && \
    rm -rf codec-base/target && \
    test -z "$(git status --porcelain)" && \
    test "$(git rev-parse HEAD)" = "'"${UPSTREAM_SHA_PARENT}"'"' \
 && echo "tree restored to pristine parent bytes; codec-base recompiles from source" \
 && cd /app/src && test ! -d codec-base/target && echo "codec-base/target removed" \
 && git -C /app/src rev-parse HEAD

# Tripwire: record the toolchain binaries' hashes (resolved through the same
# explicit PATH the verifier uses). The verifier refuses to run if any of these
# differs in the trial container, so an agent cannot score by swapping mvn/git/
# javac/java for fakes.
RUN PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin sh -c '{ sha256sum -b $(command -v mvn) $(command -v git) $(command -v javac) $(command -v java); } | sort > /opt/toolchain.sha256' \
 && cat /opt/toolchain.sha256

COPY files/ /app/
RUN chmod a+rwX /app

WORKDIR /app
CMD ["/bin/bash"]