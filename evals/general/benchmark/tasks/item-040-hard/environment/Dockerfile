FROM bench-base:python-3.12

WORKDIR /app
# Provision the base Maildirs (role inboxes) and the mail-environment dirs.
# NOTE: /srv/mail/dave and /srv/mail/carol are intentionally NOT created here;
# they are deliberately missing so the setup reflects a partially-provisioned
# host (a recovery scenario).
RUN mkdir -p /app/mailplatform /srv/mail/alice /srv/mail/bob /srv/mail/admin \
           /srv/mail/logs /srv/list/queue /etc/maillists \
    && chmod 700 /srv/mail/alice /srv/mail/bob /srv/mail/admin

COPY files/mailplatform/mailservice.py /app/mailplatform/mailservice.py
COPY files/mailplatform/listmgr.py /app/mailplatform/listmgr.py
COPY files/announce.json /etc/maillists/announce.json