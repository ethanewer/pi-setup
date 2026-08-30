FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive
WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 findutils file \
 && rm -rf /var/lib/apt/lists/*

COPY files/ /app/

CMD ["/bin/bash"]