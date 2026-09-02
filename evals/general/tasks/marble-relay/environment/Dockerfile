FROM bench-base:node-22
WORKDIR /app
ENV DEBIAN_FRONTEND=noninteractive
# C toolchain for the agent's relay build; node ships in the base image
RUN apt-get update && apt-get install -y --no-install-recommends \
      gcc libc6-dev make file python3 \
    && rm -rf /var/lib/apt/lists/*
COPY files/launcher.js /app/launcher.js
RUN chmod 0444 /app/launcher.js
