FROM bench-base:python-3.12

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server openssh-client \
        && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/

RUN bash /app/make_fixtures.sh && rm -f /app/make_fixtures.sh