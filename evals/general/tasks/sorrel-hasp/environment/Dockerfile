FROM bench-base:python-3.12

# openssl CLI is the offline key-generation tool used by the runbook.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/
