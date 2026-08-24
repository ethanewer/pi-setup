FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update \
 && apt-get install -y --no-install-recommends nginx curl \
 && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/log/nginx && touch /var/log/nginx/api_access.log
COPY files/nginx.conf /etc/nginx/nginx.conf