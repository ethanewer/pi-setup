# ---------------------------------------------------------------------------
# ballast-caboose: apache/commons-lang CharRange.contains(CharRange) gives the
# wrong answer when the negated argument's excluded block touches a domain
# boundary (empty set, or a single collapsed interval).
#
# The image clones apache/commons-lang and checks out upstream PARENT commit
# 596269f16d33cd4a20223978c245a15c898c5084 (immediately before upstream commit
# 1d6ef29ce004309e50bd91e27f0f5e80e1a57a76 fixed issue #1775), so the agent
# gets the real repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. See the golden-test extraction below,
# which uses a throwaway clone that is deleted, so the fix bytes never land
# in the working clone either.
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=596269f16d33cd4a20223978c245a15c898c5084
ARG FIX_SHA=1d6ef29ce004309e50bd91e27f0f5e80e1a57a76

ENV DEBIAN_FRONTEND=noninteractive \
    MAVEN=/opt/apache-maven-3.9.9/bin/mvn \
    M2_REPO=/opt/m2repo \
    OMP_NUM_THREADS=1

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends openjdk-21-jdk git curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL -o /opt/mvn.tgz https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz \
 && tar xzf /opt/mvn.tgz -C /opt \
 && rm -f /opt/mvn.tgz \
 && test "$(${MAVEN} -version | head -1 | grep -c 'Apache Maven 3.9.9')" = "1"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/apache/commons-lang.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}"

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes also never enter this repository; the golden
# file lives only in the image at /opt/golden/.
RUN git clone --depth 1 --no-checkout https://github.com/apache/commons-lang.git /tmp/goldensrc \
 && git -C /tmp/goldensrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/goldensrc show ${FIX_SHA}:src/test/java/org/apache/commons/lang3/CharRangeTest.java \
      > /opt/golden/CharRangeTest.java \
 && test -s /opt/golden/CharRangeTest.java \
 && grep -q "testContains_Charrange_negatedArgumentTouchingBounds" /opt/golden/CharRangeTest.java \
 && rm -rf /tmp/goldensrc \
 && chmod a+r /opt/golden/CharRangeTest.java

# ---- warm the offline Maven repository and compile the module ---------------
# test-compile builds main + test sources without running anything; the
# second step warms surefire and runs one green existing test at the parent.
RUN mkdir -p /opt/m2repo \
 && cd /app/src \
 && ${MAVEN} -B -q test-compile \
      -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
      -Dmaven.repo.local=/opt/m2repo \
 && ${MAVEN} -B -q test -Dtest='CharRangeTest#testContains_Charrange' -DfailIfNoTests=false \
      -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
      -Dmaven.repo.local=/opt/m2repo \
 && chmod -R a+rwX /opt/m2repo /app/src

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app && chmod +x /app/probe.sh \
 && cp /app/probe.sh /opt/probe.sh.pristine \
 && cp /app/Probe.java /opt/Probe.java.pristine \
 && chmod 444 /opt/probe.sh.pristine /opt/Probe.java.pristine \
 && test "$(sha256sum /app/probe.sh /opt/probe.sh.pristine | awk '{print $1}' | uniq | wc -l)" = "1" \
 && test "$(sha256sum /app/Probe.java /opt/Probe.java.pristine | awk '{print $1}' | uniq | wc -l)" = "1"

CMD ["/bin/bash"]