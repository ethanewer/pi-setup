FROM bench-base:python-3.12

WORKDIR /app

# Python numeric/ML stack + the small web framework used by the /classify
# endpoint. torch is pulled as the CPU build (default wheel on this base).
RUN pip install --no-cache-dir \
        torch \
        numpy \
        flask

# The task is authored entirely by the agent; there are no binary fixtures.
# This COPY keeps the layer so future fixtures can be added without a rebuild.
COPY files/ /app/