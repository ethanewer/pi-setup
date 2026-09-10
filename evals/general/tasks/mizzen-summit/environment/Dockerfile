ARG UPSTREAM_SHA=26b251a451ce941d3d7a55e6487bcb7f16b5ad48

FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=26b251a451ce941d3d7a55e6487bcb7f16b5ad48

# Toolchain for the kafka Gradle build. Kafka 4.3.1 targets Java 17+ (CI runs
# JDK 21); git is needed for the clone and for Gradle's commit-id receipt;
# ca-certificates keeps HTTPS trust intact for the image-build downloads.
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git openjdk-21-jdk-headless \
 && rm -rf /var/lib/apt/lists/*

# Gradle state lives under /app so the image-warm step and the trial (which may
# run as root or as uid 1000) share it. The build is hard-capped at 1 vCPU in
# the harness, so keep the worker count at 1 and the daemon heap bounded.
ENV GRADLE_USER_HOME=/app/.gradle-home \
    GRADLE_OPTS="-Dorg.gradle.workers.max=1 -Dorg.gradle.parallel=false -Dorg.gradle.jvmargs=-Xmx4g -Xss4m"

WORKDIR /app

# Apache Kafka 4.3.1, shallow clone pinned to the exact 40-hex commit the tag
# pointed at when this task was authored (tag 4.3.1 is annotated: the ref
# resolves to tag object a07059e..., whose peeled commit is 26b251a...). The
# assertion makes the build fail closed if the tag is ever force-moved
# upstream, so the image always builds the exact tree that was measured.
RUN git clone --depth 1 --branch 4.3.1 https://github.com/apache/kafka.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# Warm every cache the trial needs. This single Gradle pass downloads the
# wrapper distribution, the plugin set and every third-party dependency, and
# compiles the full dependency closure of the target module's test graph
# (clients, server-common, coordinator-common -- main and test source sets),
# then runs the module's own EventAccumulatorTest to green. The trial has no
# network, so this layer IS the warm cache: after the agent edits one file,
# the same command recompiles only what changed (measured ~50 s at 1 vCPU).
RUN cd /app/src && bash -o pipefail -c './gradlew :coordinator-common:test --tests org.apache.kafka.coordinator.common.runtime.EventAccumulatorTest 2>&1 | tail -25'

# Prove the warm layer is fully up-to-date when rerun with --offline, exactly
# as the trial and verifier will invoke it (all tasks skip in one pass).
RUN cd /app/src && bash -o pipefail -c './gradlew :coordinator-common:test --tests org.apache.kafka.coordinator.common.runtime.EventAccumulatorTest --offline 2>&1 | tail -8'

COPY files/ /app/

# The image is built as root; the trial may run as uid 1000 and must be able to
# write build artifacts into /app/src and /app/.gradle-home.
RUN chmod -R a+rwX /app && chown -R 1000:1000 /app 2>/dev/null || true

CMD ["/bin/bash"]