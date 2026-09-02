FROM bench-base:ubuntu-24.04

# R (for RStan) + Python (for PyStan), plus the C++ toolchain both samplers
# need to compile Stan models at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
        r-base r-base-dev python3 python3-pip python3-dev \
        g++ libc6-dev gcc make cmake \
    && rm -rf /var/lib/apt/lists/*

# RStan 2.32.7 from CRAN (compiled at build time so agents/verifier only pay
# the model-compile cost, not the library-compile cost).
RUN Rscript -e 'options(repos = c(CRAN = "https://cloud.r-project.org")); \
  install.packages(c("Rcpp","RcppEigen","RcppParallel","BH","StanHeaders","inline","gridExtra","loo","jsonlite"), Ncpus = 2, quiet = TRUE); \
  remotes <- c("remotes"); if (!requireNamespace("remotes", quietly=TRUE)) install.packages("remotes", Ncpus = 2, quiet = TRUE); \
  remotes::install_version("rstan", version = "2.32.7", repos = "https://cloud.r-project.org", upgrade = "never", quiet = TRUE)' \
  && rm -rf /tmp/Rtmp*

# PyStan 3.10 (pure-python + Cython; models compile at runtime with g++ libc6-dev).
ENV PIP_CERT=/etc/ssl/certs/ca-certificates.crt \
    REQUESTS_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt \
    GIT_SSL_CAINFO=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
RUN python3 -m pip install --no-cache-dir --break-system-packages "pystan==3.10.0" "pandas" "numpy"

WORKDIR /app
COPY files/ /app/