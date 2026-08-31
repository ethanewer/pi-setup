# anchor-quill: a local Postfix mail hub for Larkspur Labs. The mailing-list
# declarations must land in the canonical virtual-alias map at the fixed path
# /etc/postfix/virtual; config at any other path is not honored.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

WORKDIR /app

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        postfix procps ca-certificates && \
    rm -rf /var/lib/apt/lists/* && \
    [ -f /etc/postfix/main.cf ] || touch /etc/postfix/main.cf

# Scenario fixture: the lab's list spec the agent must apply.
COPY files/ /app/
