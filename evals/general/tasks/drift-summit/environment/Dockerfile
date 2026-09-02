# drift-summit - session-driver tooling lab environment.
# Base: bench-base:ubuntu-24.04 (contains python3.12, tmux, procps, curl already).
FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive \
    TERM=xterm

# Session-driver tooling baseline: sudo for the privilege-enumeration part and
# openssh-server so a real sshd daemon can be started headless.
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends sudo openssh-server tmux procps && \
    rm -rf /var/lib/apt/lists/* && \
    useradd -m -s /bin/bash ops && \
    mkdir -p /run/sshd /srv/site /srv/events /srv/monitor /srv/restricted \
             /srv/programs /opt/smp /app && \
    ssh-keygen -A

# Scenario fixtures: SMP debugger + program, event stream, web root, restricted
# file, and sudoers grant for user ops. (tests/ and solution/ are never copied.)
COPY files/ /

RUN chmod 440 /etc/sudoers.d/ops && \
    chmod 600 /srv/restricted/summary.txt && \
    chmod 644 /srv/site/index.html /srv/events/current.ndjson && \
    chmod 755 /opt/smp/smp_debug.py /srv/programs && \
    chmod 644 /srv/programs/fib.smp && \
    visudo -c -f /etc/sudoers.d/ops

WORKDIR /app