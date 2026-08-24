FROM bench-base:ubuntu-24.04

# socat: TCP port forwarder. psmisc: provides fuser for listener cleanup. curl: HTTP client (also inherited).
RUN apt-get update && apt-get install -y socat psmisc curl && rm -rf /var/lib/apt/lists/*

WORKDIR /app