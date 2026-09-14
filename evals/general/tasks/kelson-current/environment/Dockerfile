# kelson-current: real upstream netty/netty, codec-compression module.
# The tree is cloned at the pinned PARENT commit (the gzip FEXTRA
# header-field bug intact). The fix commit is fetched ONLY into a throwaway
# clone under /tmp, used to extract the project's own regression test into
# /opt/golden, and deleted before the image finishes; the fix object never
# enters /app/src.
ARG UPSTREAM_SHA_PARENT=6dabf563b6acdc30448f2b09685fbdcd5d88e39a
ARG UPSTREAM_SHA_FIX=a655e648bf3195eca5293bfd9b679fef8109c42c

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jdk-headless maven git \
 && rm -rf /var/lib/apt/lists/*

# Maven local repository shared by every user (the trial may run as root or
# as uid 1000, so a ~/.m2 cache under one HOME would be invisible to the
# other). Point the GLOBAL settings at /opt/m2/repository and make it
# world-writable like the sibling v4.3 tasks do for their caches.
RUN mkdir -p /opt/m2/repository \
 && printf '<settings>\n  <localRepository>/opt/m2/repository</localRepository>\n</settings>\n' > /usr/share/maven/conf/settings.xml \
 && chmod -R a+rwX /opt/m2

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned
# SHA means the object store of /app/src holds ONLY the parent commit. The
# fix commit is never fetched into this clone. Fail closed if upstream
# moves: assert HEAD equals the pin.
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/netty/netty.git \
 && git fetch --depth 1 origin $UPSTREAM_SHA_PARENT \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA_PARENT" \
 && echo "cloned at parent $UPSTREAM_SHA_PARENT"

# Extract the project's own regression test for this bug (JdkZlibTest.java
# as of the FIX commit, with the two FEXTRA regression tests) into
# /opt/golden through a SEPARATE throwaway clone under /tmp that is removed
# in the same RUN, so upstream test bytes never land in this task tree and
# the fix commit never lands in /app/src. Also snapshot the pristine
# PRE-FIX decoder source into /opt/prefix: the verifier runs the agent's
# own reproduction against that file (swapped into a scratch tree) and
# requires it to FAIL, proving the symptom is real and the reproduction
# targets it.
RUN git init /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/netty/netty.git \
 && git fetch --depth 1 origin $UPSTREAM_SHA_FIX \
 && mkdir -p /opt/golden /opt/prefix \
 && git show "$UPSTREAM_SHA_FIX:codec-compression/src/test/java/io/netty/handler/codec/compression/JdkZlibTest.java" > /opt/golden/JdkZlibTest.java \
 && test -s /opt/golden/JdkZlibTest.java \
 && grep -q "testGZIPDecodeWithExtraField" /opt/golden/JdkZlibTest.java \
 && grep -q "testConcatenatedGzipFirstStreamHasExtraField" /opt/golden/JdkZlibTest.java \
 && cp /app/src/codec-compression/src/main/java/io/netty/handler/codec/compression/JdkZlibDecoder.java /opt/prefix/JdkZlibDecoder.java \
 && test -s /opt/prefix/JdkZlibDecoder.java \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && echo "golden test + pristine pre-fix decoder extracted"

# The image is built as root; the trial may run as root or as uid 1000.
# Make the tree writable by uid 1000 and WARM every cache as that user:
# build + install the reactor closure of codec-compression (common, buffer,
# transport, codec-base, ...) once so /opt/m2 holds every dependency, and
# run the module's pre-existing JdkZlibTest once so the pre-existing suite
# is proven green at the parent commit and the test dependencies are warm.
RUN chown -R 1000:1000 /app/src \
 && su -s /bin/bash ubuntu -c 'cd /app/src && MAVEN_OPTS="-Xmx4g -Dmaven.wagon.http.pool=false" mvn -pl codec-base,codec-compression -am install -DskipTests -Dcheckstyle.skip=true -Dxml.format.skip=true' \
 && su -s /bin/bash ubuntu -c 'cd /app/src && MAVEN_OPTS="-Xmx4g -Dmaven.wagon.http.pool=false" mvn -pl codec-compression test -Dtest=JdkZlibTest -Dsurefire.failIfNoSpecifiedTests=true -Dcheckstyle.skip=true -Dxml.format.skip=true' \
 && echo "reactor closure installed; parent JdkZlibTest green"

# Belt: prove the fix commit is not reachable from the trial clone and the
# tree is still exactly at the parent commit.
RUN cd /app/src \
 && if git cat-file -e "$UPSTREAM_SHA_FIX^{commit}" 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA_PARENT" \
 && echo "fix commit unreachable from trial clone; HEAD = $(git rev-parse HEAD)"

# Lock down the golden test, the pristine pre-fix decoder and the toolchain.
# The warm passes needed a world-writable /opt/m2, and those permissions
# survive into the trial container; an adversarial agent (a root trial)
# could otherwise swap java/mvn/git for stubs, replace /opt/prefix so the
# pre-fix check fails to fail, or tamper with the golden test. Record
# sha256 pins at image build time; the verifier re-checks them before
# executing anything.
RUN mkdir -p /opt/pins \
 && sha256sum /opt/golden/JdkZlibTest.java > /opt/pins/golden.sha256 \
 && sha256sum /opt/prefix/JdkZlibDecoder.java > /opt/pins/prefix.sha256 \
 && sha256sum /usr/bin/git /usr/bin/mvn /usr/bin/java > /opt/pins/toolchain.sha256 \
 && chmod 555 /opt/pins /opt/golden /opt/prefix \
 && chmod 444 /opt/pins/*.sha256 /opt/golden/JdkZlibTest.java /opt/prefix/JdkZlibDecoder.java \
 && cd / && sha256sum -c /opt/pins/golden.sha256 >/dev/null \
 && sha256sum -c /opt/pins/prefix.sha256 >/dev/null \
 && sha256sum -c /opt/pins/toolchain.sha256 >/dev/null \
 && echo "golden + prefix + toolchain pinned"

# The trial has no network, so Maven must never try to reach Central:
# leave Maven's offline behaviour to each invocation's -o flag (documented
# in the instruction). JVM options only - MAVEN_OPTS is handed to the JVM by
# Debian's mvn launcher, so no CLI flags here.
ENV MAVEN_OPTS="-Xmx4g -Dmaven.wagon.http.pool=false"

WORKDIR /app

COPY files/ /app/
RUN chmod a+rwX /app

CMD ["/bin/bash"]