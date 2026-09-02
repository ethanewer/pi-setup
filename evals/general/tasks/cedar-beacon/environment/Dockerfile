FROM bench-base:python-3.12

RUN apt-get update && apt-get install -y --no-install-recommends gfortran \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir numpy scipy cython

WORKDIR /app

COPY files/ /app/
