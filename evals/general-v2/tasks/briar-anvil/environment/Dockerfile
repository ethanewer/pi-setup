FROM bench-base:python-3.12

RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends build-essential valgrind \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY files/ /app/
