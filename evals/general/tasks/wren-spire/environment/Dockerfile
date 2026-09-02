# wren-spire: a tiny mailing-list manager (`listd`) that reads its list
# configuration exclusively from the canonical path /etc/listd/lists.conf.
# The daemon, control script, and spool layout are image infrastructure, not
# deliverables. The agent must place the canonical config and make the
# running daemon honor it.

FROM bench-base:python-3.12

WORKDIR /app

# listd daemon + control script + documentation (in image only)
COPY listd/ /opt/listd/
RUN chmod +x /opt/listd/listd.py /opt/listd/ctl.sh /opt/listd/entry.sh \
 && mkdir -p /etc/listd /var/lib/listd /var/spool/listd /var/log \
 && touch /var/log/listd.log

ENTRYPOINT ["/opt/listd/entry.sh"]
CMD ["bash"]
