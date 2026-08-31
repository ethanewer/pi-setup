FROM bench-base:python-3.12

WORKDIR /app

# Quiet Loom analytics pod: Jupyter Server (pinned for deterministic builds).
RUN pip install --quiet --no-cache-dir "jupyter_server==2.14.2"

# Visible fixture: the deployment profile the config file reads at load time.
# The verifier rotates /app/deploy_profile.json between hidden cases.
COPY files/ /app/
