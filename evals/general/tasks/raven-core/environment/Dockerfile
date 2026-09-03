# raven-core — XXE audit + remediation across
# several XML parsing scripts (stdlib xml.sax / xml.dom.minidom only).
FROM bench-base:python-3.12

# Ship the pristine parser scripts, benign samples, and config as the agent's
# starting point. The agent patches /app/parsers/*.py in place and produces
# /app/analyze_xxe.py + /app/xxe_audit.json.
COPY files/ /app/

# Byte-for-byte pristine copies the verifier uses to re-derive the true
# pre-patch exploitability (the agent never needs to touch these).
RUN mkdir -p /opt/pristine && \
    cp -r /app/parsers /opt/pristine/parsers && \
    cp -r /app/samples /opt/pristine/samples && \
    cp /app/config.json /opt/pristine/config.json

WORKDIR /app
