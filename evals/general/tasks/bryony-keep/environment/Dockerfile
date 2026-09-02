# moor: bryony-keep -- a mailing-list configuration task for the Bryony Keep
# watchtower. The announcement-list manager (notimgr) is installed in the
# image and reads its configuration ONLY from the canonical path
# /etc/keepmsg/lists.conf. The image ships a stale canonical config (retired
# lists) and a decoy config at the WRONG path /etc/keepmsg.conf, which
# notimgr ignores by design. The agent must provision the canonical config
# from a spec JSON and save the resulting manager report.

FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        procps ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Infrastructure: the list-manager control tool (image only, not a deliverable).
COPY keepmsg/ /opt/keepmsg/
RUN chmod +x /opt/keepmsg/notimgr.py && mkdir -p /etc/keepmsg /app

# Pre-seed the canonical config with RETIRED lists (the agent's run must
# replace them with exactly the declared lists), and a decoy config at the
# WRONG path (notimgr never reads /etc/keepmsg.conf).
RUN printf '%s\n' \
      '# Bryony Keep -- retired watch rosters (superseded by the new spec).' \
      '' \
      '[gate-book@watch.bryony.example]' \
      'members = old.turnkey@bryony.example, second.turnkey@bryony.example' \
      '' \
      '[LAMPLIGHTERS@watch.bryony.example]' \
      'members = retired.keeper@bryony.example' \
      > /etc/keepmsg/lists.conf \
 && printf '%s\n' \
      '# WARNING: legacy deployment wrote its list map here (WRONG PATH).' \
      '# notimgr honors only /etc/keepmsg/lists.conf.' \
      '' \
      '[allwatch@watch.bryony.example]' \
      'members = ghost.warden@bryony.example' \
      > /etc/keepmsg.conf

# Scenario fixture: the list specification the agent provisions from.
# This is NOT the answer; the answer is the canonical config + the report.
COPY files/ /app/

CMD ["/bin/bash"]
