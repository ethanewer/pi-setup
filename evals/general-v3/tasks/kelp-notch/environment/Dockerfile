# kelp-notch: Thornway Makerspace mailing-list provisioning. Postfix is
# installed as a local-only MTA; the canonical virtual-alias map
# (/etc/postfix/virtual) is intentionally NOT configured. Two local recipient
# accounts exist. The agent's provisioning script must wire the lists through
# the canonical file.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

# preseed postfix so it installs headless as a local-only MTA
RUN echo 'postfix postfix/mailname string thornway.internal' | debconf-set-selections \
 && echo 'postfix postfix/main_mailer_type string "Local only"' | debconf-set-selections \
 && echo 'postfix postfix/destinations string "thornway.internal localhost localhost.localdomain"' | debconf-set-selections

RUN apt-get update && apt-get install -y --no-install-recommends \
        postfix \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Local delivery targets for the lists
RUN useradd -m -s /bin/bash steward \
 && useradd -m -s /bin/bash warden

# Fixture: the visible list spec (NOT the answer; hidden specs differ).
COPY files/ /app/

CMD ["/bin/bash"]
