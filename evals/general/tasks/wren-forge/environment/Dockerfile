FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# R + rstan (Stan compile toolchain included), jsonlite for the summary.
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        build-essential \
        r-base \
        r-cran-rstan \
        r-cran-rcpp \
        r-cran-jsonlite \
    && rm -rf /var/lib/apt/lists/*

# Ubuntu's r-cran-bh ships only a stub with no real Boost headers, which makes
# Stan model compilation fail. Install the real header package from CRAN.
RUN R --vanilla -e 'options(repos=c(CRAN="https://cloud.r-project.org")); install.packages("BH", quiet=TRUE)' \
    >/tmp/bh.log 2>&1 && rm -f /tmp/bh.log

WORKDIR /app

COPY files/ /app/
