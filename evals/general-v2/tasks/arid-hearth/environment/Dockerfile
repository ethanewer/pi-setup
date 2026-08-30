FROM bench-base:ubuntu-24.04

RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY files/list/store.py /app/list/store.py
COPY files/list/list.conf /app/list/list.conf
RUN chmod +x /app/list/store.py

CMD ["/bin/bash"]