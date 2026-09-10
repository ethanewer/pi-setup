# keelson-berth: greenfield Java 21 + Maven HTTP catalogue service.
#
# Tools: JDK 21 (headless), Maven 3.8.7, SQLite 3 CLI, curl, python3.
# The container has NO network at trial time, so the Maven local repository
# at /opt/m2repo is pre-seeded below by compiling, testing and packaging a
# throwaway project that carries exactly the dependency/plugin pins of
# /app/maven-template/pom.xml.  Agents (and the verifier) always pass
# -Dmaven.repo.local=/opt/m2repo to every mvn invocation.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        openjdk-21-jdk-headless maven sqlite3 curl >/dev/null 2>&1 && \
    rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 \
    PATH=/usr/lib/jvm/java-21-openjdk-amd64/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    M2_REPO=/opt/m2repo


WORKDIR /app
RUN chmod 777 /app

COPY files/ /app/

# ---------------------------------------------------------------------------
# Pre-seed the offline Maven repository.  Downloads happen here, where the
# network exists; trial-time mvn invocations run fully offline.
# ---------------------------------------------------------------------------
RUN mkdir -p /opt/m2repo /tmp/m2seed && \
    cd /tmp/m2seed && \
    mkdir -p src/main/java/m2seed src/test/java/m2seed && \
    printf 'package m2seed;\npublic class Starter {\n  public static void main(String[] args) {}\n}\n' > src/main/java/m2seed/Starter.java && \
    printf 'package m2seed;\nimport org.junit.jupiter.api.Test;\nimport static org.junit.jupiter.api.Assertions.assertTrue;\npublic class SmokeTest {\n  @Test void passes() { assertTrue(true); }\n}\n' > src/test/java/m2seed/SmokeTest.java && \
    cp /app/maven-template/pom.xml pom.xml && \
    mvn -q -B -Dmaven.repo.local=/opt/m2repo clean verify && \
    mvn -q -B -Dmaven.repo.local=/opt/m2repo dependency:copy-dependencies -DoutputDirectory=/tmp/m2seed/deps && \
    rm -rf /tmp/m2seed && \
    chmod -R a+rwX /opt/m2repo

# Build the visible development fixture database from its seed script.
RUN sqlite3 /app/db/items.sqlite < /app/db/seed.sql && \
    chmod -R a+rX /app