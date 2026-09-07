FROM bench-base:ubuntu-24.04

WORKDIR /app

# --- git over SSH server setup ---
RUN apt-get update && apt-get install -y git openssh-client openssh-server \
    && rm -rf /var/lib/apt/lists/*

# dedicated git-over-ssh user
# A later RUN in this file builds a git repository, so it is root-owned, and git
# refuses to operate on a repository owned by another user: it exits 128 with
# "detected dubious ownership". Whether the trial works then depends on which
# user the harness runs it as. Record the exception in /etc/gitconfig rather
# than root's ~/.gitconfig so it holds for every user, and use the wildcard
# because agents also clone into directories of their own.
RUN git config --system --add safe.directory '*'
RUN useradd -m -d /home/sshgit sshgit && \
    mkdir -p /home/sshgit/repos && \
    git init -b main --bare /home/sshgit/repos/team.git

# seed the bare repo with one commit
RUN mkdir -p /tmp/seed && cd /tmp/seed && \
    git init -q -b main . && \
    git config user.email "seed@example.com" && \
    git config user.name "Seed" && \
    printf 'ssh-hello\n' > README.txt && \
    git add -A && \
    git commit -q -m "seed commit" && \
    git remote add origin /home/sshgit/repos/team.git && \
    git push -q -u origin main && \
    rm -rf /tmp/seed

# client identity key authorized for sshgit
RUN mkdir -p /keys && ssh-keygen -q -t ed25519 -N '' -f /keys/agent_key && \
    mkdir -p /home/sshgit/.ssh && \
    cp /keys/agent_key.pub /home/sshgit/.ssh/authorized_keys && \
    chmod 700 /home/sshgit/.ssh && \
    chmod 600 /home/sshgit/.ssh/authorized_keys && \
    chown -R sshgit /home/sshgit

# entrypoint starts sshd at container boot
COPY files/entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh
ENTRYPOINT ["/root/entrypoint.sh"]

WORKDIR /app