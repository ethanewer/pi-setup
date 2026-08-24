FROM bench-base:python-3.12

WORKDIR /app
RUN mkdir -p /app/mailplatform /srv/mail /srv/list/queue /srv/mail/logs /etc/maillists
COPY files/mailplatform/mailservice.py /app/mailplatform/mailservice.py
COPY files/mailplatform/listmgr.py /app/mailplatform/listmgr.py