FROM bench-base:python-3.12

WORKDIR /app

# Willow Bridge field-support harness toolchain (jupyter server, vim, gawk, jq).
RUN pip install --quiet --no-cache-dir "notebook" && \
    apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gawk >/dev/null && \
    rm -rf /var/lib/apt/lists/*

# Visible fixture: a small labeled-but-untrimmed sample IP listing the agent can
# use to smoke-test /app/ipv4_octet.awk locally. NOT graded by the verifier.
COPY files/ /app/