ARG UPSTREAM_SHA_PARENT=5367a2d0687ec4c1901f693559cd4d2d14ca65d1
ARG UPSTREAM_SHA_FIX=55524c66de8db4c2e44727b69421c7d0e4f30be0

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA_PARENT
ARG UPSTREAM_SHA_FIX

# Toolchain: OpenJDK 21 (>= 8 required), git, curl. No Maven: the project's
# java/ sources compile with plain javac against a small set of annotation,
# test and runtime jars.
RUN apt-get update \
 && apt-get install -y --no-install-recommends openjdk-21-jdk-headless curl ca-certificates git \
 && rm -rf /var/lib/apt/lists/*

# Dependency jars from Maven Central, exactly as the mining container used.
# CRITICAL: truth must be 0.28 (the version guava's own pom pinned in this era).
# A newer truth (e.g. 0.44) calls Strings.lenientFormat, which did not exist in
# 2016 guava, so the golden SplitterTest then dies with NoSuchMethodError.
RUN mkdir -p /opt/jars && cd /opt/jars \
 && for u in \
      com/google/errorprone/error_prone_annotations/2.3.4/error_prone_annotations-2.3.4.jar \
      org/checkerframework/checker-qual/2.5.0/checker-qual-2.5.0.jar \
      com/google/j2objc/j2objc-annotations/1.3/j2objc-annotations-1.3.jar \
      com/google/code/findbugs/jsr305/1.3.9/jsr305-1.3.9.jar \
      org/codehaus/mojo/animal-sniffer-annotations/1.18/animal-sniffer-annotations-1.18.jar \
      com/google/guava/failureaccess/1.0.1/failureaccess-1.0.1.jar \
      junit/junit/4.13.2/junit-4.13.2.jar \
      org/hamcrest/hamcrest-core/1.3/hamcrest-core-1.3.jar \
      com/google/truth/truth/0.28/truth-0.28.jar ; do \
   curl -sL -O "https://repo.maven.apache.org/maven2/$u" || exit 1 ; done \
 && ls /opt/jars | wc -l

# Clone the REAL upstream repository at exactly the parent commit, with the
# shallowest possible history: `git init` + one depth-1 fetch of the pinned SHA
# means the object store in /app/src holds ONLY the parent commit. The fix
# commit (which an agent must not be able to look up or fetch) is never fetched
# into this clone, and the trial container has no network anyway.
RUN git init -q /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/google/guava.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_PARENT} \
 && git checkout -q --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Extract the project's own regression test for this bug (the two methods the
# upstream fix commit appends to SplitterTest) into /opt/golden using a
# THROWAWAY clone that is deleted immediately afterwards, so upstream test
# bytes never land in this task tree and the fix commit never lands in /app/src.
# AndroidIncompatible.java is the same-directory annotation the test file needs
# to compile and is identical at the parent commit.
RUN git init -q /tmp/upstream-fix-clone \
 && cd /tmp/upstream-fix-clone \
 && git remote add origin https://github.com/google/guava.git \
 && git fetch --depth 1 origin ${UPSTREAM_SHA_FIX} \
 && mkdir -p /opt/golden \
 && git show ${UPSTREAM_SHA_FIX}:guava-tests/test/com/google/common/base/SplitterTest.java > /opt/golden/SplitterTest.java \
 && git show ${UPSTREAM_SHA_FIX}:guava-tests/test/com/google/common/base/AndroidIncompatible.java > /opt/golden/AndroidIncompatible.java \
 && test -s /opt/golden/SplitterTest.java \
 && test -s /opt/golden/AndroidIncompatible.java \
 && grep -q "testPatternSplitWordBoundary_singleCharInput" /opt/golden/SplitterTest.java \
 && grep -q "testPatternSplitWordBoundary_singleWordInput" /opt/golden/SplitterTest.java \
 && cd / \
 && rm -rf /tmp/upstream-fix-clone \
 && test ! -e /tmp/upstream-fix-clone

# Belt: prove the fix commit is not reachable from the trial clone, and that
# the clone is at the pinned parent commit.
RUN cd /app/src \
 && if git cat-file -e ${UPSTREAM_SHA_FIX}^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi \
 && test "$(git rev-parse HEAD)" = "${UPSTREAM_SHA_PARENT}" \
 && test "$(git rev-parse --is-shallow-repository)" = "true"

# The trial may run as root or as uid 1000; make the whole tree writable so the
# agent can edit the real source file in place and compile scratch into /tmp.
WORKDIR /app
RUN chmod -R a+rwX /app/src && chmod a+rwX /app

# Authored convenience files for the agent: build recipe only. No reproduction
# is shipped; the agent must write its own.
# guava/src compiles from scratch in well under a minute at 1 vCPU, so there is
# no need for a warm precompiled class tree in the image.
COPY files/ /app/

CMD ["/bin/bash"]