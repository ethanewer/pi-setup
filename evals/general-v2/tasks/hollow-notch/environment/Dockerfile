# Hollow-notch task image. A small, invented "palisade" three-node store.
# Clean-room: no reference-suite content. Services run on localhost, no systemd.
FROM bench-base:ubuntu-24.04

COPY files/palisade/ /app/palisade/

WORKDIR /app

# --- Install the service toolchain (kept lean; no systemd/GPU/X) -------------
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      openjdk-17-jdk-headless \
      postfix \
      tcpdump \
      whois \
      jq \
      sudo \
      ca-certificates \
      openssl \
      netcat-openbsd \
      iproute2 \
      procps \
      coreutils \
      grep \
      sed \
 && rm -rf /var/lib/apt/lists/*

# Build the JVM daemon from the provided fixture source (now that JDK exists).
RUN cd /app/palisade \
 && javac -d /tmp/palbuild /app/palisade/PalisadeDaemon.java \
 && mkdir -p /app/palisade/classes && cp /tmp/palbuild/*.class /app/palisade/classes/ \
 && echo 'Main-Class: PalisadeDaemon' > /tmp/MANIFEST.MF \
 && jar cmf /tmp/MANIFEST.MF /app/palisade/palisade.jar -C classes . \
 && rm -rf /tmp/palbuild /tmp/MANIFEST.MF /app/palisade/classes

# Local subscribers whose mailboxes the palisade announcement list fans out to.
RUN useradd --no-create-home --shell /usr/sbin/nologin sable \
 && useradd --no-create-home --shell /usr/sbin/nologin rona \
 && useradd --no-create-home --shell /usr/sbin/nologin trio \
 && mkdir -p /var/mail /var/run/palisade \
 && chmod 0775 /var/mail

# --- Bake in a deliberately BROKEN initial state the agent must repair ------
# 1) hostname is an unqualified short label, not the intended FQDN
RUN printf 'host3\n' > /etc/hostname
# 2) The intended site FQDN is NOT resolvable out of the box: docker does not
#    inject it and there is no DNS entry for the invented hollow.farm zone,
#    so `getent hosts <host>` fails until the host is added to /etc/hosts.
# 3) nsswitch "hosts" line is fragmented to "files" only (no dns fallback)
RUN cp /etc/nsswitch.conf /etc/nsswitch.conf.orig \
 && sed -i 's/^hosts:.*/hosts:      files/' /etc/nsswitch.conf
# 4) mail relay deliberately hijacked: every message is forced outbound via a
#    relayhost and mydestination excludes the site, so list mail is not local.
RUN printf 'myhostname = host3.localdomain\nmydomain = localdomain\nmyorigin = $myhostname\nrelayhost = smtp.invalid.hollow.farm:2525\ndestination_concurrency_limit = 2\n' > /etc/postfix/main.cf \
 && printf 'inet_interfaces = loopback-only\ninet_protocols = ipv4\n' >> /etc/postfix/main.cf

WORKDIR /app