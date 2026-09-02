FROM bench-base:python-3.12

# tar, gzip, file and xxd are used to build, inspect and validate artifacts.
RUN apt-get update -y \
 && apt-get install -y --no-install-recommends tar gzip file xxd \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/ /app/