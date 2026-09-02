FROM bench-base:ubuntu-24.04
WORKDIR /app
RUN apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    gcc libopenmpi-dev openmpi-bin python3 curl >/dev/null 2>&1 \
 && rm -rf /var/lib/apt/lists/*
# Pre-stage the pinned Hadoop 3.3.6 release tarball so the provisioning step
# is deterministic (no slow/flaky network fetch at agent time). verify with
# the shipped sha512 before extracting; the task still requires installing it.
COPY hadoop-3.3.6.tar.gz /opt/
COPY hadoop-3.3.6.tar.gz.sha512 /opt/
COPY files/ /app/