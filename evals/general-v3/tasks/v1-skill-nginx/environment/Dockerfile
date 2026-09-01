FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends nginx && rm -rf /var/lib/apt/lists/*

RUN mkdir -p /app/www && printf 'Harbor nginx probe index\n' > /app/www/index.html