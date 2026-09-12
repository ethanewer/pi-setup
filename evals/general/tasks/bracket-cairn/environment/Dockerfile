# bracket-cairn: junit-team/junit5 — nested classes of the same enclosing
# class or interface are enumerated via Class#getDeclaredClasses() and returned
# in raw JVM reflection order, which the JVM API explicitly leaves unspecified,
# so test suites that declare several nested test classes in one enclosing
# class run them in an order that differs between JDK versions and machines.
# This is real upstream issue #4839; the fix commit must stay invisible to the
# agent, so:
#
#   * the working clone (/app/src) is a brand-new repository that fetches ONLY
#     the parent commit by SHA. The default-branch tip (which contains the
#     fixed code) is never fetched and neither is the fix commit, so neither is
#     reachable from the object store;
#   * the project's own regression test for the bug is extracted from the fix
#     commit at image-build time into /opt/golden/ from a THROWAWAY bare clone
#     that is deleted immediately afterwards. Upstream bytes never enter this
#     task repository.
#
# The Gradle 9.0.0 wrapper distribution, plugin set and the whole
# platform-tests dependency closure are downloaded and compiled once at build
# time, so the offline trial is purely incremental.

ARG UPSTREAM_SHA=8307cd49221d90413c66918c7b094274078a6809
ARG FIX_SHA=cb577cf95050cd7b2f64090261fe5a48acb326bc

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=8307cd49221d90413c66918c7b094274078a6809
ARG FIX_SHA=cb577cf95050cd7b2f64090261fe5a48acb326bc

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git curl openjdk-21-jdk-headless \
 && rm -rf /var/lib/apt/lists/*

# git safe.directory (the trial may run as uid 1000) + build identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# JDK 24.0.2 (Temurin): the build's default Java toolchain; the Gradle daemon
# runs on it (gradle-daemon-jvm.properties sets toolchainVersion=24).
RUN curl -fsSL -o /tmp/jdk24.tgz \
      "https://github.com/adoptium/temurin24-binaries/releases/download/jdk-24.0.2%2B12/OpenJDK24U-jdk_x64_linux_hotspot_24.0.2_12.tar.gz" \
 && mkdir -p /opt/jdk-24.0.2+12 \
 && tar -xzf /tmp/jdk24.tgz -C /opt/jdk-24.0.2+12 --strip-components=1 \
 && rm /tmp/jdk24.tgz \
 && /opt/jdk-24.0.2+12/bin/java -version 2>&1 | head -1

# JDK 25.0.4.1 (Temurin): used by a few build tasks in the dependency closure;
# advertised to Gradle through $JDK25 (org.gradle.java.installations.fromEnv).
RUN curl -fsSL -o /tmp/jdk25.tgz \
      "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_x64_linux_hotspot_25.0.4.1_1.tar.gz" \
 && mkdir -p /opt/jdk-25.0.4.1+1 \
 && tar -xzf /tmp/jdk25.tgz -C /opt/jdk-25.0.4.1+1 --strip-components=1 \
 && rm /tmp/jdk25.tgz \
 && /opt/jdk-25.0.4.1+1/bin/java -version 2>&1 | head -1

ENV JAVA_HOME=/opt/jdk-24.0.2+12 \
    PATH=/opt/jdk-24.0.2+12/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    JDK21=/usr/lib/jvm/java-21-openjdk-amd64 \
    JDK24=/opt/jdk-24.0.2+12 \
    JDK25=/opt/jdk-25.0.4.1+1 \
    GRADLE_USER_HOME=/app/.gradle-home \
    GRADLE_OPTS="-Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx3g -XX:MaxMetaspaceSize=1g"

WORKDIR /app

# ---- working clone: ONLY the buggy parent commit ----------------------------
RUN git init /app/src \
 && cd /app/src \
 && git remote add origin https://github.com/junit-team/junit5.git \
 && git fetch --depth 1 origin "$UPSTREAM_SHA" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git remote remove origin \
 && git gc --prune=now --quiet \
 && git rev-parse HEAD

# ---- golden regression test, extracted from the FIX commit ------------------
# Throwaway bare clone; deleted right after the extraction, so the fix commit
# never exists inside /app/src/.git.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/junit-team/junit5.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$FIX_SHA:platform-tests/src/test/java/org/junit/platform/commons/util/ReflectionUtilsTests.java" \
      > /opt/golden/ReflectionUtilsTests.java \
 && test -s /opt/golden/ReflectionUtilsTests.java \
 && grep -q "findNestedClassesWithMultipleNestedClasses" /opt/golden/ReflectionUtilsTests.java \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- warm every cache at build time (the trial has no network) ---------------
# First pass (online): downloads the Gradle 9.0.0 wrapper distribution
# (SHA256-pinned by the wrapper), the plugin set, every third-party dependency,
# compiles the full test graph of :platform-tests and runs the two reflection
# test classes green. This layer IS the warm cache for the offline trial.
RUN cd /app/src && bash -o pipefail -c './gradlew :platform-tests:test \
      --tests "org.junit.platform.commons.util.ReflectionUtilsTests" \
      --tests "org.junit.platform.commons.support.ReflectionSupportTests" \
      -Ptesting.enableJaCoCo=false 2>&1 | tail -25'

# Second pass: prove the fully-warm state reruns with --offline, exactly as the
# trial and the verifier will invoke it (all tasks skip; only the tests run).
RUN cd /app/src && bash -o pipefail -c './gradlew :platform-tests:test \
      --tests "org.junit.platform.commons.util.ReflectionUtilsTests" \
      --tests "org.junit.platform.commons.support.ReflectionSupportTests" \
      -Ptesting.enableJaCoCo=false --offline 2>&1 | tail -12'

COPY files/ /app/

# The image is built as root; the trial may run as root or uid 1000 and both
# must be able to write build artifacts and share the warm Gradle caches.
RUN chmod -R a+rwX /app && chown -R 1000:1000 /app 2>/dev/null || true

CMD ["/bin/bash"]