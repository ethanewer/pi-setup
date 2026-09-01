# marlin-berth: Gullwing Press relay MTA. Postfix is installed (preseeded so
# apt is headless) but not run as a daemon; the agent provisions the canonical
# mailing-list configuration with the postfix tooling.

FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# preseed postfix so it installs headless as a local-only MTA
RUN echo 'postfix postfix/mailname string harborside.net' | debconf-set-selections \
 && echo 'postfix postfix/main_mailer_type string "Local only"' | debconf-set-selections \
 && echo 'postfix postfix/destinations string "lists.harborside.net localhost localhost.localdomain"' | debconf-set-selections

RUN apt-get update && apt-get install -y --no-install-recommends \
        postfix \
        python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Fixture: the authoritative list table (NOT the answer).
COPY files/ /app/

ENV LANG=C.UTF-8
CMD ["/bin/bash"]
