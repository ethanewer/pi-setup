# ---------------------------------------------------------------------------
# capstan-hull: apache/commons-lang Fraction.multiplyBy throws a spurious
# ArithmeticException ("overflow: mulPos") whenever either operand is not
# reduced to lowest terms, even when the correctly reduced product fits an
# int. Fixed upstream in 10f4421456b891d5a426348511383f387c99f3e1 (issue
# #1769) by reducing both operands before the Knuth 4.5.1 cross-gcd pass.
#
# The image clones apache/commons-lang and checks out upstream PARENT commit
# 9d1f110190081801754a8a0b447693ad2407a502, so the agent gets the real
# repository with the real bug still in it.
#
# The clone is created with `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detached there, so the ONLY commit object in the /app/src
# object store is the parent itself. Neither the fix commit nor any later
# history is reachable from /app/src. The golden regression test is extracted
# from the fix commit with a THROWAWAY clone that is deleted afterwards, so
# the fix bytes never land in the working clone. See the belt check below.
# ---------------------------------------------------------------------------
FROM bench-base:ubuntu-24.04

ARG UPSTREAM_SHA=9d1f110190081801754a8a0b447693ad2407a502
ARG FIX_SHA=10f4421456b891d5a426348511383f387c99f3e1

ENV DEBIAN_FRONTEND=noninteractive \
    MAVEN=/opt/apache-maven-3.9.9/bin/mvn \
    M2_REPO=/opt/m2repo \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1

# Toolchain: OpenJDK 21 (the project builds fine on 21) + Maven 3.9.9 from
# archive.apache.org, exactly the versions the mining container used and what
# the reproduction recipe expects.
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
RUN git clone -q --depth 1 --no-checkout https://github.com/apache/commons-lang.git /tmp/goldensrc \
 && git -C /tmp/goldensrc fetch -q --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden \
 && git -C /tmp/goldensrc show ${FIX_SHA}:src/test/java/org/apache/commons/lang3/math/FractionTest.java \
      > /opt/golden/FractionTest.java \
 && test -s /opt/golden/FractionTest.java \
 && grep -q "testMultiply" /opt/golden/FractionTest.java \
 && grep -q "testDivide" /opt/golden/FractionTest.java \
 && grep -q "463410000" /opt/golden/FractionTest.java \
 && rm -rf /tmp/goldensrc \
 && chmod a+r /opt/golden/FractionTest.java

# ---- warm the offline Maven repository and compile the module ---------------
# test-compile builds main + test sources without running anything; the
# second step warms surefire and runs the two green existing test methods at
# the parent (the regression assertions on top of those methods only exist in
# the fix commit). Every trial-time mvn invocation reuses /opt/m2repo.
RUN mkdir -p /opt/m2repo \
 && cd /app/src \
 && ${MAVEN} -B -q test-compile \
      -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
      -Dmaven.repo.local=/opt/m2repo \
 && ${MAVEN} -B -q test -Dtest='FractionTest#testMultiply+testDivide' -DfailIfNoTests=false \
      -Dspotless.check.skip=true -Dcheckstyle.skip=true -Drat.skip=true -Denforcer.skip=true \
      -Dmaven.repo.local=/opt/m2repo \
 && chmod -R a+rwX /opt/m2repo /app/src

WORKDIR /app

COPY files/ /app/

RUN chmod -R a+rwX /app && chmod +x /app/probe.sh

# ---- belt: prove the bug is alive in the image and the fix is absent -------
# FractionProbe (shipped via files/) exits 1 and prints THREW on the buggy
# parent tree; the belt asserts exactly that against the freshly cloned tree.
RUN cd /app/src \
 && mkdir -p /tmp/probe \
 && javac -d /tmp/probe /app/FractionProbe.java src/main/java/org/apache/commons/lang3/math/Fraction.java 2>/tmp/probe-err.log \
 && (java -cp /tmp/probe org.apache.commons.lang3.math.FractionProbe > /tmp/belt.out 2>&1) \
 && echo "BELT: bug did NOT reproduce at parent (probe exited 0); aborting" && exit 1 \
 || true \
 && grep -q "THREW java.lang.ArithmeticException: overflow: mulPos" /tmp/belt.out \
 && echo "BELT: bug reproduced at parent (THREW overflow: mulPos as expected)" \
 && rm -rf /tmp/probe /tmp/belt.out /tmp/probe-err.log

CMD ["/bin/bash"]