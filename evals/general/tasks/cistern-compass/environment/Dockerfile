# cistern-compass: junit-team/junit5 — unquoted CSV columns are trimmed with
# String.strip() (Unicode-aware whitespace) instead of the ASCII-only
# String.trim(), so Unicode White_Space above U+0020 (NBSP U+00A0, thin space
# U+2009, ideographic space U+3000, ...) started being silently removed from
# parameterized-test argument values while non-whitespace control characters
# below U+0020 (NUL U+0000, ...) were no longer trimmed at all. Real upstream
# issue #4692; the fix commit must stay invisible to the agent, so:
#
#   * the working clone (/app/src) is a brand-new repository that fetches ONLY
#     the parent commit by SHA. The default-branch tip (which contains the
#     fixed code) is never fetched and neither is the fix commit, so neither is
#     reachable from the object store;
#   * the project's own regression test for the bug is extracted from the fix
#     commit at image-build time into /opt/golden/ from a THROWAWAY bare clone
#     that is deleted immediately afterwards, and is then OVERLAID onto the
#     working tree exactly as the mining reproduction did (`git checkout <FIX>
#     -- jupiter-tests/.../CsvArgumentsProviderTests.java`), so the failing
#     regression test is part of the delivered tree. Upstream bytes never
#     enter this task repository.
#
# Gradle 8.14.2-bin wrapper distribution (SHA256-pinned in the tree), the
# plugin set and the whole :jupiter-tests dependency closure are downloaded
# and compiled once at build time, so the offline trial is purely incremental.

ARG UPSTREAM_SHA=f8513cbd8b867f0c4252d4d9625d77edc45820cb
ARG FIX_SHA=2a52a0643fba15b52fcf13dd553758fcbc1d0458

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=f8513cbd8b867f0c4252d4d9625d77edc45820cb
ARG FIX_SHA=2a52a0643fba15b52fcf13dd553758fcbc1d0458

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
 && git show "$FIX_SHA:jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java" \
      > /opt/golden/CsvArgumentsProviderTests.java \
 && test -s /opt/golden/CsvArgumentsProviderTests.java \
 && grep -q "trimsSpacesUsingStringTrim" /opt/golden/CsvArgumentsProviderTests.java \
 && cd / \
 && rm -rf /tmp/fixsrc

# ---- overlay the regression test onto the working tree ----------------------
# Exactly the mining reproduction: at the parent commit, the FIX-commit version
# of the project's own regression-test class is swapped into the working tree,
# so
#   ./gradlew :jupiter-tests:test --tests "...CsvArgumentsProviderTests" ...
# fails inside the image with the mined symptom.
RUN cp /opt/golden/CsvArgumentsProviderTests.java \
      /app/src/jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java \
 && cd /app/src \
 && test "$(git diff --name-only)" = "jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java" \
 && cmp -s /opt/golden/CsvArgumentsProviderTests.java \
        jupiter-tests/src/test/java/org/junit/jupiter/params/provider/CsvArgumentsProviderTests.java \
 && ! git cat-file -e "${FIX_SHA}^{commit}"

# ---- warm every cache at build time (the trial has no network) ---------------
# First pass (online): downloads the Gradle 8.14.2 wrapper distribution
# (SHA256-pinned by the wrapper), the plugin set and every third-party
# dependency, and compiles the whole :jupiter-tests test graph. Because the
# overlaid regression test is present and the bug is real, the run must FAIL;
# the layer fails closed on the mined symptom and carries on.
RUN cd /app/src && bash -c './gradlew :jupiter-tests:test \
      --tests "org.junit.jupiter.params.provider.CsvArgumentsProviderTests" \
      -Ptesting.enableJaCoCo=false > /tmp/warm-online.log 2>&1; \
    rc=$?; test "$rc" -ne 0 \
    && grep -q "trimsSpacesUsingStringTrim" /tmp/warm-online.log'

# Second pass: prove the fully-warm state reruns with --offline, exactly as the
# trial and the verifier will invoke it, and still fails with the same symptom.
RUN cd /app/src && bash -c './gradlew :jupiter-tests:test \
      --tests "org.junit.jupiter.params.provider.CsvArgumentsProviderTests" \
      -Ptesting.enableJaCoCo=false --offline > /tmp/warm-offline.log 2>&1; \
    rc=$?; test "$rc" -ne 0 \
    && grep -q "trimsSpacesUsingStringTrim" /tmp/warm-offline.log'

COPY files/ /app/

# The image is built as root; the trial may run as root or uid 1000 and both
# must be able to write build artifacts and share the warm Gradle caches.
RUN chmod -R a+rwX /app && chown -R 1000:1000 /app 2>/dev/null || true

CMD ["/bin/bash"]