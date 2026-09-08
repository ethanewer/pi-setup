# zephyr-vault task image: a small Flask web app (SQLi-aware audit source +
# hardened render identity server) plus a provided spreadsheet REST mock.
# CPU-only, loopback HTTP, no internet beyond pip at build time.
FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir flask==3.1.3 requests==2.34.2

# Provided fixtures: legacy audit source and the spreadsheet REST mock.
COPY files/src/ /app/src/

RUN mkdir -p /app/data

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]