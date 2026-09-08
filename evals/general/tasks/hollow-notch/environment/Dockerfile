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
# (Pre-baked before anything else: the claude-code agent CLI is installed here so
# the eval harness's agent-installer — which needs working DNS — is skipped at
# trial time; it is inert for task semantics and for other agents.)
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && curl -fsSL https://downloads.claude.ai/claude-code-releases/bootstrap.sh | bash -s -- \
 && ln -sf /root/.local/bin/claude /usr/local/bin/claude \
 && claude --version
# 3) This task used to fragment the nsswitch "hosts" line to "files" only, with no
#    dns fallback. That was removed, and the reason matters more than the line.
#
#    Disabling DNS in this container disables the agent, not just the task. Two of
#    the three harnesses (claude-code and pi) are installed agents: their CLI runs
#    inside the container and calls the LLM API over the network. With no dns
#    fallback, `curl https://openrouter.ai` fails with "Could not resolve host",
#    verified by running this image. claude-code retried the API ten times, gave
#    up with UnknownApiError, and produced a transcript containing one synthetic
#    message and no assistant turn; pi produced four assistant messages with null
#    content. Both scored 0 on both models. Four of the six measured pairs could
#    not attempt the task at all, and the zeros were charged to the models as
#    though they had tried.
#
#    Only terminus-2 was unaffected, because harbor drives its tmux session from
#    the host, so its API calls never traverse the container's resolver. A task
#    that one harness can attempt and four cannot is not measuring the models.
#
#    The sabotage was also redundant. The site FQDN has no DNS zone, so the agent
#    must add it to /etc/hosts regardless of the nsswitch line; that is where the
#    name-resolution work in this task actually lives. tests/check.py still asserts
#    the hosts line contains both files and dns, which now passes on a stock image
#    and serves as a guard against the agent breaking it.
#
#    Pre-baking the CLI above does not help: it covers installation, which needs
#    DNS once at build time, not operation, which needs it on every API call.
# 4) mail relay deliberately hijacked: every message is forced outbound via a
#    relayhost and mydestination excludes the site, so list mail is not local.
RUN printf 'myhostname = host3.localdomain\nmydomain = localdomain\nmyorigin = $myhostname\nrelayhost = smtp.invalid.hollow.farm:2525\ndestination_concurrency_limit = 2\n' > /etc/postfix/main.cf \
 && printf 'inet_interfaces = loopback-only\ninet_protocols = ipv4\n' >> /etc/postfix/main.cf

WORKDIR /app