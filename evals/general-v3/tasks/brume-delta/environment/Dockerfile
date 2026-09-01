FROM bench-base:ubuntu-24.04

WORKDIR /app

# ShoreDFS site-config templates, the node emulator, the client, and a
# visible smoke-test ops file. python3 ships with the ubuntu base.
COPY files/conf/ /app/conf/
COPY files/opt/shoredfs/ /opt/shoredfs/
COPY files/examples/ /app/examples/

RUN chmod +x /opt/shoredfs/dfsnode.py /opt/shoredfs/dfsclient.py \
    && mkdir -p /app/run
