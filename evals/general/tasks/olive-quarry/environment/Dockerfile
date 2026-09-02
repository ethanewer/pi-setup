FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- R stack + jupyter tooling (the workbench runtime, deliberately NOT
# ---- commissioned: no kernelspec registered, vendored packages uninstalled)
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        r-base-core \
        r-cran-irkernel \
    && rm -rf /var/lib/apt/lists/*
RUN pip install -q jupyter ipykernel

WORKDIR /app

COPY files/ /app/

# pristine state guard: make sure no user kernelspec exists yet
RUN rm -rf /root/.local/share/jupyter/kernels
