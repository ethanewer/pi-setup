FROM bench-base:python-3.12

WORKDIR /app

# Harborlight CI notebook toolchain: jupyter server.
RUN pip install --quiet --no-cache-dir "notebook" && \
    rm -rf /root/.cache/pip

# Visible deploy descriptor so the agent can see the format and smoke-test.
# NOT graded byte-for-byte; the verifier rotates this file between cases.
COPY files/ /app/

RUN mkdir -p /tmp/ph_root
