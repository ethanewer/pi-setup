# nock-trestle: upstream-clone regression task on trinodb/trino (SQL parser).
#
# The upstream repository is cloned, SHA-pinned and shallow at /app/src while
# the image builds (network exists at build time; the trial has none). The
# whole toolchain, the Maven local repository and a compiled copy of the
# target module are baked into the image so the trial only does incremental
# work. A small authored regression (environment/files/seed-interval-fields.patch)
# is applied on top of the pristine checkout so the trial starts broken: the
# module's own test suite is the bug report the agent must chase.

FROM bench-base:ubuntu-24.04

# trinodb/trino master, resolved 2026-09-10 by the author via
# `git ls-remote https://github.com/trinodb/trino.git refs/heads/master`.
# A branch can be force-moved upstream; the 40-hex hash is the pin.
ARG UPSTREAM_SHA=0984974677197ff76bae9fc4f4950eb30a96306a

# git-uid-1000 safety and a build identity (agents may want to commit).
RUN git config --system --add safe.directory '*' \
    && git config --system user.email "build@localhost" \
    && git config --system user.name "build"

# Toolchain: apt basics, Temurin JDK 25 (Trino 484 requires JDK 25;
# apt's own openjdk is 21), and Maven 3.9.16 (the version of Maven that
# Trino's own maven wrapper pins in .mvn/wrapper/maven-wrapper.properties).
RUN apt-get update -y \
    && apt-get install -y --no-install-recommends curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/jdk25.tar.gz "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_x64_linux_hotspot_25.0.4.1_1.tar.gz" \
    && mkdir -p /opt/java \
    && tar -xzf /tmp/jdk25.tar.gz -C /opt/java --strip-components=1 \
    && rm -rf /tmp/jdk25.tar.gz

RUN curl -fsSL -o /tmp/maven.tar.gz "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.tar.gz" \
    && tar -xzf /tmp/maven.tar.gz -C /opt \
    && rm -rf /tmp/maven.tar.gz

ENV JAVA_HOME=/opt/java
ENV PATH=/opt/java/bin:/opt/apache-maven-3.9.16/bin:$PATH

# Clone shallow, then check out the pinned commit. The pin is an immutable
# 40-hex commit that was master's tip when resolved; fetching it by SHA keeps
# the build reproducible even after upstream master moves on. Fail closed if
# the checked-out head ever differs from the pin.
RUN git clone --depth 1 --branch master https://github.com/trinodb/trino.git /app/src \
    && cd /app/src \
    && git fetch --depth 1 origin "$UPSTREAM_SHA" \
    && git checkout --detach "$UPSTREAM_SHA" \
    && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA"

WORKDIR /app/src

# Warm the Maven local repository and compile the target module and its
# reactor (trino-grammar) once, on the pristine tree, so everything the trial
# can need is already cached. -DskipTests keeps this to compile+package.
RUN mvn -B -V -pl core/trino-parser -am install -DskipTests \
    -Dmaven.source.skip=true -Dair.check.skip-all=true -Dmaven.javadoc.skip=true \
    --no-snapshot-updates --no-transfer-progress

# One online run of the FULL trino-parser test suite on the pristine tree:
# primes surefire providers, junit-platform, assertj and every test-scope
# dependency, and proves the module suite is green before the seed goes in.
RUN mvn -B -f core/trino-parser/pom.xml \
    -Dmaven.source.skip=true -Dair.check.skip-all=true -Dmaven.javadoc.skip=true \
    test

# Prove the trial's exact workflow works with no network at all: run the same
# test phase fully offline (a small passing class filter keeps the build
# green even though the regression is not applied yet; test compilation still
# resolves every dependency offline).
RUN mvn -B -o -f core/trino-parser/pom.xml \
    -Dmaven.source.skip=true -Dair.check.skip-all=true -Dmaven.javadoc.skip=true \
    -Dtest=TestSqlParserErrorHandling -Dsurefire.failIfNoSpecifiedTests=false \
    test

# Apply the authored regression on top of the pristine checkout and COMMIT
# it, so the tree's HEAD itself carries the bug. The trial starts broken;
# the module's own suite is the bug report the agent must chase. (Committing
# also means restoring the working tree with git checkout/reset cannot wipe
# the bug, and every genuine fix necessarily leaves a source diff.)
COPY files/seed-interval-fields.patch /tmp/seed-interval-fields.patch
RUN cd /app/src \
    && git apply /tmp/seed-interval-fields.patch \
    && git add core/trino-parser/src/main/java/io/trino/sql/parser/AstBuilder.java \
    && git commit -q -m "Fix year-month interval field handling" \
    && rm -f /tmp/seed-interval-fields.patch

WORKDIR /app