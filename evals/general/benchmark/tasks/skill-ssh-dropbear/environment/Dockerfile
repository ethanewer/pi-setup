FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y openssh-client dropbear \
    && rm -rf /var/lib/apt/lists/*

# dedicated user + private payload
RUN mkdir -p /keys /etc/dropbear && useradd -m -d /home/bob bob && \
    printf 'dropbear-secret-here\n' > /home/bob/secret.txt && chown bob /home/bob/secret.txt

# DropBear RSA host key for the server
RUN dropbearkey -t rsa -s 2048 -f /etc/dropbear/dropbear_rsa_key

# client identity key (OpenSSH format) authorized for bob
RUN mkdir -p /home/bob/.ssh && \
    ssh-keygen -q -t ed25519 -N '' -f /keys/agent_key && \
    cp /keys/agent_key.pub /home/bob/.ssh/authorized_keys && \
    chmod 700 /home/bob/.ssh && \
    chmod 600 /home/bob/.ssh/authorized_keys && \
    chown -R bob /home/bob

COPY files/entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh
ENTRYPOINT ["/root/entrypoint.sh"]