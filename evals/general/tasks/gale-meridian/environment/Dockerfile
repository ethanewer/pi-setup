FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- system layer: R runtime + jupyter tooling (python side)
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        r-base-core \
    && rm -rf /var/lib/apt/lists/*

RUN pip install -q \
        jupyter_core \
        jupyter_client \
        nbformat \
        nbclient \
        nbconvert \
        ipykernel

# ---- vendored (NOT installed) R analysis packages + IRkernel, for offline use
# The agent must install these from /app/vendor; nothing below installs them.
RUN mkdir -p /app/vendor/partial \
    && apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends --download-only \
        -o Dir::Cache::archives=/app/vendor \
        r-cran-irkernel r-cran-jsonlite r-cran-data.table libzmq5 \
    && rm -rf /var/lib/apt/lists/*

# ---- platform fixtures (the *unprovisioned* state is created below)
COPY files/ /app/

# 1) no user kernelspec exists (fresh image); 2) a stale broken kernelspec
# from an older image must be removed/repaired by the provisioning script:
# its argv[0] does not exist, violating kernelspec integrity.
RUN mkdir -p /usr/local/share/jupyter/kernels/legacy-r \
    && printf '%s\n' \
      '{' \
      ' "argv": ["/usr/bin/R-definitely-missing", "--slave", "-e", "IRkernel::main()", "--args", "{connection_file}"],' \
      ' "display_name": "R legacy worker",' \
      ' "language": "R"' \
      '}' > /usr/local/share/jupyter/kernels/legacy-r/kernel.json

WORKDIR /app
