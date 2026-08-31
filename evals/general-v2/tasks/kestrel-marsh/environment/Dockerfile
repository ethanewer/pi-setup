FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- system layer: R 4.x + compilers + ZeroMQ headers (pbdZMQ needs these)
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        r-base-core \
        r-base-dev \
        build-essential \
        libzmq3-dev \
    && rm -rf /var/lib/apt/lists/*

# ---- python layer: jupyter toolchain able to register and execute kernels.
# NOTE: no IRkernel R package and no R kernelspec are installed here; the R
# package closure must be built offline from /app/offline-repo by the agent.
RUN pip install -q \
        jupyter_core \
        jupyter_client \
        nbformat \
        nbclient \
        nbconvert \
    && rm -rf /root/.cache/pip

COPY files/ /app/

# Broken state: a stale kernelspec whose R binary no longer exists.
RUN mkdir -p /root/.local/share/jupyter/kernels/r_old \
    && printf '%s\n' '{"argv": ["/usr/bin/r-obsolete", "--vanilla", "-e", "IRkernel::main()", "--args", "{connection_file}"], "display_name": "R Legacy (broken)", "language": "R"}' \
       > /root/.local/share/jupyter/kernels/r_old/kernel.json

WORKDIR /app
