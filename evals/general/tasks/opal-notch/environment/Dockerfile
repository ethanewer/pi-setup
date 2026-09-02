FROM bench-base:python-3.12

WORKDIR /app

# Deterministic service accounts, each starting on a restricted or alternate
# shell, plus an explicit /etc/shells listing every legal target shell.
RUN useradd -m -s /usr/sbin/nologin relqa \
 && useradd -m -s /bin/sh relbuild \
 && useradd -m -s /usr/sbin/nologin relaudit \
 && useradd -m -s /bin/sh relmail \
 && useradd -m -s /usr/sbin/nologin relops \
 && for s in /bin/sh /bin/bash /bin/dash /usr/sbin/nologin; do grep -qx "$s" /etc/shells || echo "$s" >> /etc/shells; done

COPY files/ /app/