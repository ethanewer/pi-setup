FROM bench-base:python-3.12

# Pillow and numpy are used by the deliverable generator (Pillow renders out.jpg).
RUN pip install --no-cache-dir pillow numpy

WORKDIR /app
COPY files/ /app/
