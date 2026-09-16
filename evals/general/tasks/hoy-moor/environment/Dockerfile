# hoy-moor: junit-team/junit5 — a package-private test method inherited from a
# superclass in a different package is silently dropped from discovery and
# execution as soon as a subclass declares a method with the same name and
# parameter list (upstream issue #5098), because method selectors are deduplicated
# by class-name + method-name + parameter types only, ignoring the declaring
# class that Java's visibility rules say matters. The fix commit must stay
# invisible to the agent, so:
#
#   * the working clone (/app/src) is a brand-new repository that fetches ONLY
#     the parent commit by SHA. The default-branch tip (which contains the
#     fixed code) is never fetched and neither is the fix commit, so neither is
#     reachable from the object store;
#   * the project's own regression tests for the bug are extracted from the fix
#     commit at image-build time into /opt/golden/ from a THROWAWAY bare clone
#     under /tmp that is deleted immediately afterwards, so the fix object never
#     enters the shipped repository.
#
# The Gradle 9.2.0-bin wrapper distribution (SHA256-pinned in the tree), the
# plugin set and the whole :jupiter-tests dependency closure are downloaded and
# compiled once at build time, so the offline trial is purely incremental.

ARG UPSTREAM_SHA=f5b43ce4e82796d225fe6ecbbfe8a0ad1bed27c4
ARG FIX_SHA=1866c0c21b177f10364aafb17d6b61dd7c80e476

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=f5b43ce4e82796d225fe6ecbbfe8a0ad1bed27c4
ARG FIX_SHA=1866c0c21b177f10364aafb17d6b61dd7c80e476

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git curl openjdk-21-jdk-headless \
 && rm -rf /var/lib/apt/lists/*

# git safe.directory (the trial may run as uid 1000) + build identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# JDK 24.0.2 (Temurin): used by a few build tasks in the dependency closure;
# advertised to Gradle through $JDK24 (org.gradle.java.installations.fromEnv).
RUN curl -fsSL -o /tmp/jdk24.tgz \
      "https://github.com/adoptium/temurin24-binaries/releases/download/jdk-24.0.2%2B12/OpenJDK24U-jdk_x64_linux_hotspot_24.0.2_12.tar.gz" \
 && mkdir -p /opt/jdk-24.0.2+12 \
 && tar -xzf /tmp/jdk24.tgz -C /opt/jdk-24.0.2+12 --strip-components=1 \
 && rm /tmp/jdk24.tgz \
 && /opt/jdk-24.0.2+12/bin/java -version 2>&1 | head -1

# JDK 25.0.4.1 (Temurin): the build's default Java toolchain and the Gradle
# daemon JVM (gradle/gradle-daemon-jvm.properties sets toolchainVersion=25).
RUN curl -fsSL -o /tmp/jdk25.tgz \
      "https://github.com/adoptium/temurin25-binaries/releases/download/jdk-25.0.4.1%2B1/OpenJDK25U-jdk_x64_linux_hotspot_25.0.4.1_1.tar.gz" \
 && mkdir -p /opt/jdk-25.0.4.1+1 \
 && tar -xzf /tmp/jdk25.tgz -C /opt/jdk-25.0.4.1+1 --strip-components=1 \
 && rm /tmp/jdk25.tgz \
 && /opt/jdk-25.0.4.1+1/bin/java -version 2>&1 | head -1

ENV JAVA_HOME=/opt/jdk-25.0.4.1+1 \
    PATH=/opt/jdk-25.0.4.1+1/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
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

# ---- warm every cache at build time (the trial has no network) ---------------
# First pass (online): downloads the Gradle 9.2.0 wrapper distribution
# (SHA256-pinned by the wrapper), the plugin set, every third-party dependency,
# compiles the full test graph of :jupiter-tests and runs the tree's own engine
# test slice green. This layer IS the warm cache for the offline trial.
RUN cd /app/src && bash -o pipefail -c './gradlew :jupiter-tests:test \
      --tests "org.junit.jupiter.engine.LifecycleMethodOverridingTests" \
      --tests "org.junit.jupiter.engine.OverloadedTestMethodTests" \
      --tests "org.junit.jupiter.engine.discovery.DiscoverySelectorResolverTests" \
      --tests "org.junit.jupiter.engine.discovery.DiscoveryTests" \
      -Ptesting.enableJaCoCo=false 2>&1 | tail -25'

# Second pass: prove the fully-warm state reruns with --offline, exactly as the
# trial and the verifier will invoke it.
RUN cd /app/src && bash -o pipefail -c './gradlew :jupiter-tests:test \
      --tests "org.junit.jupiter.engine.LifecycleMethodOverridingTests" \
      --tests "org.junit.jupiter.engine.OverloadedTestMethodTests" \
      --tests "org.junit.jupiter.engine.discovery.DiscoverySelectorResolverTests" \
      --tests "org.junit.jupiter.engine.discovery.DiscoveryTests" \
      -Ptesting.enableJaCoCo=false --offline 2>&1 | tail -12'

# ---- golden regression tests, extracted from the FIX commit -----------------
# Throwaway bare clone; deleted immediately afterwards, so the fix commit never
# exists inside /app/src/.git and the golden tests are never in the shipped tree.
RUN git init --bare /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/junit-team/junit5.git \
 && git fetch --depth 1 origin "$FIX_SHA" \
 && mkdir -p /opt/golden \
 && git show "$FIX_SHA:jupiter-tests/src/test/java/org/junit/jupiter/engine/TestMethodOverridingTests.java" \
      > /opt/golden/TestMethodOverridingTests.java \
 && git show "$FIX_SHA:jupiter-tests/src/test/java/org/junit/jupiter/engine/subpackage/SuperClassWithPackagePrivateLifecycleMethodInDifferentPackageTestCase.java" \
      > /opt/golden/SuperClassWithPackagePrivateLifecycleMethodInDifferentPackageTestCase.java \
 && test -s /opt/golden/TestMethodOverridingTests.java \
 && grep -q "bothPackagePrivateTestMethodsAreDiscovered" /opt/golden/TestMethodOverridingTests.java \
 && grep -q "invokedSuper" /opt/golden/SuperClassWithPackagePrivateLifecycleMethodInDifferentPackageTestCase.java \
 && cd / \
 && rm -rf /tmp/fixsrc

COPY files/ /app/

# The image is built as root; the trial may run as root or uid 1000 and both
# must be able to write build artifacts and share the warm Gradle caches.
RUN chmod -R a+rwX /app && chown -R 1000:1000 /app /opt/golden 2>/dev/null || true

CMD ["/bin/bash"]