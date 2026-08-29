FROM bench-base:ubuntu-24.04

# The task exercises secure file erasure (coreutils shred) and crypto via the
# openssl enc command, with a real consultable manual page (man openssl-enc).
# The minimized base diverts the real man-db `man` binary (see
# /usr/bin/man.REAL) in favour of a "unminimize" stub; restore the real one so
# `man` actually renders pages. Shipping a clean-room manual for the tool at
# /usr/share/man/man1/openssl-enc.1 guarantees the man page exists to read.
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
        coreutils openssl python3 man-db groff-base strace \
 && rm -rf /var/lib/apt/lists/* \
 && if [ -f /usr/bin/man.REAL ]; then \
      rm -f /usr/bin/man && cp /usr/bin/man.REAL /usr/bin/man; \
    fi

WORKDIR /app

# Scenario fixtures (fictional, authored for this task only).
COPY files/ /app/

# The clean-room manual page for the tool's `enc` subcommand.
COPY man/openssl-enc.1 /usr/share/man/man1/openssl-enc.1