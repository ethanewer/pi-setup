FROM bench-base:ubuntu-24.04

WORKDIR /app

# Interactive numeric vault: a bash state machine that clears the screen,
# prints coloured ANSI prompts, and refuses to read from a plain pipe
# (read -s needs a real tty), so interacting with it requires a PTY.
COPY files/vault.sh /app/vault.sh
RUN chmod +x /app/vault.sh