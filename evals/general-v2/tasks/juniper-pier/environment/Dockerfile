# Juniper Pier — Bayesian statistical modeling (PyStan posterior + penalty selection)
FROM bench-base:python-3.12

# PyStan's httpstan backend compiles the model extension with a C++ compiler
# on first use inside the container.
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends g++ make \
    && rm -rf /var/lib/apt/lists/*

# numpy/scipy: numerics; scikit-learn + pandas: penalty selection engine.
RUN pip install --no-cache-dir \
    numpy scipy scikit-learn pandas pystan

WORKDIR /app

COPY files/ /app/