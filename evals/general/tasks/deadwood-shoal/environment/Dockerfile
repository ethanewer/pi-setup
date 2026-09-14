# deadwood-shoal: apache/commons-lang -- StringUtils.leftPad / rightPad crash
# the JVM with OutOfMemoryError when the requested size makes the pad-count
# subtraction overflow (upstream issue LANG-1828, PR #1736).
#
# The image clones apache/commons-lang SHALLOW at the PARENT commit (the real
# upstream bug is present in the working tree) and pre-builds the module and
# its tests with Maven 3.9.9 on JDK 21 as cached layers, so everything the
# trial needs runs offline and the agent's edit-compile-test cycle is one
# incremental Maven run. The upstream FIX's own regression test
# (src/test/.../StringUtilsTest.java at the fix commit) is extracted at build
# time into /opt/golden through a throwaway bare clone under /tmp that is
# deleted, so the fix commit object is never reachable from /app/src/.git.
#
# The working clone is created with `git init` + `git fetch --depth 1 origin
# <parent-sha>` so that NO ref exists and NO commit other than the parent is
# in the object store.  A plain `git clone --depth 1` would also fetch the
# live default-branch tip; even though the fix COMMIT object is hidden behind
# the shallow boundary, `git show origin/master:src/main/java/...` would then
# hand the agent the FIXED source of StringUtils.java straight out of the
# clone with no network.  That leak was found in review and is closed here:
# with no refs and a single commit, the answer content cannot exist on disk.
# The pre-fix compiled classes are snapshotted into /opt/prefix-classes so
# the verifier can run the agent's own reproduction against the buggy class
# set. As a fail-closed check, the build itself runs the golden regression
# test against the parent tree and aborts unless it reproduces the mined
# OutOfMemoryError. commons-lang is not a Terminal-Bench 2.1 source
# repository (checked against specs/tb21_source_repositories.json).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PATH=/opt/apache-maven-3.9.9/bin:/usr/local/bin:/usr/bin:/bin

ARG UPSTREAM_SHA=170e9f28ad2667a9b0c80480c2a5a13cb4a53257
ARG FIX_SHA=ae85262f04df19b6307de18758cfdcc31cae733d

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# --- build toolchain ----------------------------------------------------------
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jdk git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /opt/mvn.tgz https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz \
 && tar xzf /opt/mvn.tgz -C /opt \
 && /opt/apache-maven-3.9.9/bin/mvn -v

# ---- working clone: buggy parent commit, fix commit unreachable --------------
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/apache/commons-lang.git \
 && git fetch --depth 1 origin 170e9f28ad2667a9b0c80480c2a5a13cb4a53257 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && test -z "$(git show-ref)" \
 && [ "$(git log --all --oneline | wc -l)" = "1" ] \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway bare clone, so the fix commit never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/apache/commons-lang.git \
 && git fetch --depth 1 origin ae85262f04df19b6307de18758cfdcc31cae733d \
 && mkdir -p /opt/golden \
 && git show ae85262f04df19b6307de18758cfdcc31cae733d:src/test/java/org/apache/commons/lang3/StringUtilsTest.java \
      > /opt/golden/StringUtilsTest.java \
 && test "$(sha256sum /opt/golden/StringUtilsTest.java | cut -d' ' -f1)" \
      = "b88cc61c00b97295d7b76158dd4c5283db0e9363fd0a6874a36b5cc1bbad561f" \
 && grep -q 'leftPad("abc", Integer.MIN_VALUE' /opt/golden/StringUtilsTest.java \
 && grep -q 'rightPad("abc", Integer.MIN_VALUE' /opt/golden/StringUtilsTest.java \
 && chmod -R a+rX /opt/golden \
 && cd / && rm -rf /tmp/fixsrc

# ---- pre-build the module with Maven (cached layer, offline-warm cache) ------
RUN cd /app/src && mvn -B -q test-compile \
    -Dspotless.check.skip=true -Dcheckstyle.skip=true \
    -Drat.skip=true -Denforcer.skip=true

# Snapshot the compiled classes exactly as they are at the BUGGY parent, so
# the verifier can run the agent's reproduction against the pre-fix behaviour.
RUN mkdir -p /opt/prefix-classes \
 && cp -r /app/src/target/classes/. /opt/prefix-classes/ \
 && test -f /opt/prefix-classes/org/apache/commons/lang3/StringUtils.class \
 && chmod -R a+rX /opt/prefix-classes

# Warm the surefire/JUnit-platform cache with a real (passing-at-parent) test
# run, so the verifier's Maven test run is fully offline.
RUN cd /app/src && mvn -B -q test \
    -Dtest='StringUtilsTest#testLeftPad_StringIntChar' -DfailIfNoTests=false \
    -Dspotless.check.skip=true -Dcheckstyle.skip=true \
    -Drat.skip=true -Denforcer.skip=true

# ---- fail-closed: the mined failure must reproduce in this image ------------
# Overlay the upstream regression test onto the parent tree and require the
# targeted run to crash exactly as mined (surefire fork OOM dump, mvn exit 1),
# then restore the pristine tree.  The build ABORTS on any deviation: a golden
# test that passes at the parent, a log without the OOM+leftPad stack, or a
# tree that is not clean after the restore.
RUN cp /opt/golden/StringUtilsTest.java \
      /app/src/src/test/java/org/apache/commons/lang3/StringUtilsTest.java
RUN cd /app/src \
 && if mvn -B -q test \
        -Dtest='StringUtilsTest#testLeftPad_StringIntChar' -DfailIfNoTests=false \
        -Dspotless.check.skip=true -Dcheckstyle.skip=true \
        -Drat.skip=true -Denforcer.skip=true \
        > /tmp/golden-parent.log 2>&1; then \
        echo "GOLDEN TEST PASSED AT PARENT: THE BUG DID NOT REPRODUCE" >&2; \
        exit 1; \
    fi \
 && grep -q "Java heap space" /tmp/golden-parent.log \
 && DUMP=$(ls target/surefire-reports/*jvmRun1.dump 2>/dev/null | head -1) \
 && { [ -n "$DUMP" ] || { echo "NO SUREFIRE DUMP AT PARENT" >&2; exit 1; }; } \
 && grep -q "OutOfMemoryError" "$DUMP" \
 && grep -q "StringUtils.leftPad" "$DUMP" \
 && rm -f /tmp/golden-parent.log \
 && git checkout -- \
      src/test/java/org/apache/commons/lang3/StringUtilsTest.java \
 && { [ -z "$(git status --porcelain)" ] || { echo "TREE NOT CLEAN AFTER RESTORE" >&2; exit 1; }; } \
 && echo "PARENT-SIDE GOLDEN FAILURE CONFIRMED: OutOfMemoryError at leftPad"

WORKDIR /app

# The build above ran as root.  Drop the build tree (the trial starts from
# scratch so resource copies are new files owned by the trial user) and hand
# the whole checkout to uid 1000, the uid the trial runs as, so no root-owned
# file ever needs to be overwritten or re-owned.  Maven caches stay warm in
# both /root/.m2 and /home/ubuntu/.m2.
RUN rm -rf /app/src/target \
 && chown -R 1000:1000 /app/src \
 && chmod -R a+rwX /app/src \
 && chmod a+rwX /app \
 && chmod a+rx /root \
 && chmod -R a+rwX /root/.m2 \
 && mkdir -p /home/ubuntu \
 && cp -a /root/.m2 /home/ubuntu/ \
 && chmod -R a+rwX /home/ubuntu/.m2

CMD ["/bin/bash"]