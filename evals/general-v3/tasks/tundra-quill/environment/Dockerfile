FROM bench-base:node-22

WORKDIR /app

# The task is authored entirely by the agent; there are no binary fixtures.
# This COPY keeps the layer so future fixtures can be added without a rebuild.
COPY files/ /app/
