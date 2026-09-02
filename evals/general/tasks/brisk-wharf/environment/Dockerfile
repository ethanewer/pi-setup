FROM bench-base:python-3.12
WORKDIR /app
# Toolchain + services for the Meridian Coast rendezvous cluster.
# torch (CPU) is pulled from the pytorch CPU index; the rest come from apt/pip.
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
         build-essential libopenmpi-dev openmpi-bin libssl-dev \
         postfix mlmmj mailutils \
    && rm -rf /var/lib/apt/lists/*
RUN pip install --no-cache-dir torch \
        --index-url https://download.pytorch.org/whl/cpu \
        --extra-index-url https://pypi.org/simple \
    && pip install --no-cache-dir boto3 awscli 'moto[server]'
COPY files/ /app/
