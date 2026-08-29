FROM bench-base:python-3.12

WORKDIR /app

# Deterministic toolchain the agent relies on: the uv project manager (for the
# self-contained uv project), node/npm and zsh available as platform tooling.
# The web/SSH servers and miniconda itself are deliberately NOT baked in: the
# agent must bring those in non-interactively (apt-get) and install the pinned
# miniconda from the pre-seeded installer. git ships preinstalled in the base.
RUN pip install --quiet --no-cache-dir --no-warn-script-location uv \
 && apt-get update -y -q \
 && apt-get install -y -q --no-install-recommends nodejs npm zsh \
 && rm -rf /var/lib/apt/lists/*

# A pinned, official Miniconda installer the agent must use (never run here).
# Pinned to Miniconda3-py312 24.9.2 so `conda --version` is deterministic.
RUN curl -fsSL \
        https://repo.anaconda.com/miniconda/Miniconda3-py312_24.9.2-0-Linux-x86_64.sh \
        -o /opt/miniconda-installer.sh \
    && chmod +x /opt/miniconda-installer.sh \
    && /usr/bin/python3 -c "import os;assert os.path.getsize('/opt/miniconda-installer.sh')>50000000"

# Local (offline) pip wheel index the pinned packages install from.
COPY files/gale-index/ /opt/gale-index/

RUN /usr/bin/python3 -c "print('fathom env ready')"