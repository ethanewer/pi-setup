FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- toolchain: compilers + numpy 2.x, Cython, setuptools (all offline afterwards)
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        build-essential \
        python3-dev \
    && rm -rf /var/lib/apt/lists/* \
    && pip install -q "numpy>=2.0" "cython<3.1" setuptools

COPY files/ /app/

WORKDIR /app
