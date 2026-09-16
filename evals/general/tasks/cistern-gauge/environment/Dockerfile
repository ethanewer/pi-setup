FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# Java 21 toolchain, Maven, git and the java trust-store bridge so Maven can
# reach repo.maven.apache.org through the benchmark's corporate CA.
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        openjdk-21-jdk-headless \
        maven \
        git \
        ca-certificates-java \
    && rm -rf /var/lib/apt/lists/*

# The reactor repository is built at image-build time, so it is root-owned;
# record a system-wide safe.directory so git works for whichever user the
# trial runs as. A committer identity is needed for the build-time commits.
RUN git config --system --add safe.directory '*'
RUN git config --system user.email "build@localhost" \
 && git config --system user.name "build"

WORKDIR /app
COPY files/ /app/

# Generate the reactor repository with its git history. gen_repo.py deletes
# itself and the sibling generator modules as soon as their sources are in
# memory, so the repository never tracks them.
RUN python3 /app/gen_repo.py /app

# Prove the reactor is green before the agent arrives and warm the local
# Maven cache (including the clean plugin the verifier's `clean verify` needs
# offline); the second, offline run proves the cache is complete so the trial
# (network_mode: none) can build. target/ dirs are then removed.
RUN cd /app && mvn -q -B clean verify && mvn -q -o -B clean

CMD ["/bin/bash"]