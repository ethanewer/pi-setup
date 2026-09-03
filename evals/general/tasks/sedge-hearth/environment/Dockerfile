FROM bench-base:python-3.12

# sedge-hearth — token-based auth service bench.
# Ships a read-only loopback HTTP framework stub (/app/lib/httpkit.py) and a
# visible config (/app/config.json). The agent authors the sole deliverable
# /app/token_service.py; the verifier drives it over loopback with the
# shipped config and with generated hidden configs.

WORKDIR /app

COPY files/ /app/

# Pristine byte copies of the shipped fixtures, used by the verifier to
# detect tampering (the agent must not modify either file).
COPY files/lib/httpkit.py /opt/pristine/httpkit.py
COPY files/config.json /opt/pristine/config.json

# State directory for the persistence blacklist (the service must also
# create it if missing, but ship it empty).
RUN mkdir -p /app/state