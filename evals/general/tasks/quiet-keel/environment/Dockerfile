FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Service accounts provisioned with non-login shells.
RUN useradd -M -d /var/lib/deploy-bot   -s /usr/sbin/nologin deploy-bot \
 && useradd -M -d /var/lib/audit-runner -s /bin/false         audit-runner \
 && useradd -M -d /var/lib/pipeline-svc -s /usr/sbin/nologin pipeline-svc
