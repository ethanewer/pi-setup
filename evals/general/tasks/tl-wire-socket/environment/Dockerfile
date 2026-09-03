# tl-wire-socket -- WebSocket server-side handshake + frame codec bench.
#
# Ships the sockkit TCP server skeleton (image-only, never the answer) and
# the visible config. The agent authors /app/ws_server.py against the
# documented protocol subset; the verifier swaps /app/config.json for hidden
# configs (different ports/paths) and probes with its own raw-socket client.
FROM bench-base:python-3.12

WORKDIR /app

# Visible fixtures: /app/config.json and /app/lib/sockkit.py.
COPY files/ /app/

# Pristine byte-copy of sockkit for verifier tamper detection.
COPY files/lib/sockkit.py /opt/pristine/sockkit.py