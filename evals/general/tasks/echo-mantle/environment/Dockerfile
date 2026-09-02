FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# preseed postfix so it installs headless as a local-only MTA
RUN echo 'postfix postfix/mailname string relay.internal' | debconf-set-selections \
 && echo 'postfix postfix/main_mailer_type string "Local only"' | debconf-set-selections \
 && echo 'postfix postfix/destinations string "relay-bank.internal localhost localhost.localdomain"' | debconf-set-selections

RUN apt-get update && apt-get install -y --no-install-recommends \
        openjdk-17-jre-headless \
        openjdk-17-jdk-headless \
        postfix \
        tcpdump \
        whois \
        jq \
        sudo \
        curl \
        netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Build the tiny JVM daemon into a runnable jar (JDK used only at build time).
COPY files/lib/ /app/buildsrc/
RUN mkdir -p /app/lib /app/buildobj \
 && javac -nowarn -d /app/buildobj /app/buildsrc/Relay.java \
 && (cd /app/buildobj && jar cf /app/lib/relay.jar Relay.class) \
 && rm -rf /app/buildsrc /app/buildobj

# Fixtures the agent will work on
COPY files/fixtures/ /app/fixtures/

# A real account whose default login shell is degraded on purpose
RUN useradd -m -s /usr/sbin/nologin mailreader \
 && mkdir -p /app/run

# the reported host must NOT pre-resolve; harmless baseline only
ENV LANG=C.UTF-8
CMD ["/bin/bash"]