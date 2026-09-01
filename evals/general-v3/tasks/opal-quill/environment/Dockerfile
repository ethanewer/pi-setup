FROM bench-base:python-3.12

# numpy only: synthesis + spectrum checks use numpy; the wav writer is stdlib.
RUN pip install --no-cache-dir --disable-pip-version-check numpy

WORKDIR /app

COPY files/ /app/
