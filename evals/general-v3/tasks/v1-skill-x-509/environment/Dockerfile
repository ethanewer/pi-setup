FROM bench-base:ubuntu-24.04

WORKDIR /app

# openssl is used to generate the X.509 self-signed certificate.
RUN apt-get update && apt-get install -y openssl && rm -rf /var/lib/apt/lists/*