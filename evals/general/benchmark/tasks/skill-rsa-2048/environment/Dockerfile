FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*

COPY files/message.txt /app/message.txt
RUN openssl genrsa -out /app/private.pem 2048 \
    && openssl rsa -in /app/private.pem -pubout -out /app/public.pem