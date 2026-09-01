FROM bench-base:python-3.12

# sudo + runuser (util-linux) are needed for the escalation-path exercise.
RUN apt-get update && apt-get install -y --no-install-recommends sudo && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# --- accounts ---------------------------------------------------------------
RUN groupadd -g 2104 opscrew && \
    useradd -m -g opscrew -s /bin/bash ops && \
    chown ops:opscrew /home/ops

# --- the (deliberately narrow) sudo policy ----------------------------------
# ops may elevate exactly one binary, the sealing tool, with no password.
COPY files/sealctl /usr/local/bin/sealctl
RUN chown root:root /usr/local/bin/sealctl && chmod 0755 /usr/local/bin/sealctl && \
    printf 'ops ALL=(ALL:ALL) NOPASSWD: /usr/local/bin/sealctl\n' > /etc/sudoers.d/sealbox && \
    chmod 0440 /etc/sudoers.d/sealbox

# --- root-only seal vault (starts empty) ------------------------------------
RUN mkdir -p /var/lib/sealvault && \
    chown root:root /var/lib/sealvault && chmod 0700 /var/lib/sealvault

CMD ["/bin/bash"]
