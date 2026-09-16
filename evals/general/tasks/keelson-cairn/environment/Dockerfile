# keelson-cairn: kedd journal daemon - graceful shutdown repair.
# bench-base:ubuntu-24.04 carries the JDK toolchain; the daemon is pure JVM.
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# JDK (build + runtime) and git (needed only to assemble the repository at
# image build time; the checked-in tree stays available to the agent).
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      openjdk-21-jdk-headless \
      git \
 && rm -rf /var/lib/apt/lists/*

# Building a repository in the image: any user (the trial runs as uid 1000)
# must be able to read it, and build-time commits need an identity.
RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app

# The checked-in fixture tree, assembled into /app/kedd as a git repository
# with an incremental commit history (see kgen/assemble.sh).
COPY files/ /app/fixture/
RUN bash /app/fixture/kgen/assemble.sh /app/fixture/kedd /app/kedd \
 && rm -rf /app/fixture

# Prove the shipped project builds and its semantic check suite is green
# before the agent ever arrives.
RUN bash /app/kedd/build.sh \
 && bash /app/kedd/tests/check.sh

CMD ["/bin/bash"]