FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

# Mint the visible fixtures deterministically at build time (no network).
RUN python3 /app/make_locker.py
