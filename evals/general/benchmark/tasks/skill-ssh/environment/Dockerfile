FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y openssh-client openssh-server \
    && rm -rf /var/lib/apt/lists/*

# dedicated SSH user + private payload
RUN mkdir -p /keys && useradd -m -d /home/alice alice && \
    printf 'ssh-secret-hello-world\n' > /home/alice/secret.txt && chown alice /home/alice/secret.txt

# client identity key authorized for alice
RUN mkdir -p /home/alice/.ssh && \
    ssh-keygen -q -t ed25519 -N '' -f /keys/agent_key && \
    cp /keys/agent_key.pub /home/alice/.ssh/authorized_keys && \
    chmod 700 /home/alice/.ssh && \
    chmod 600 /home/alice/.ssh/authorized_keys && \
    chown -R alice /home/alice

COPY files/entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh
ENTRYPOINT ["/root/entrypoint.sh"]