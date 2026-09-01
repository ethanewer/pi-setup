FROM bench-base:python-3.12
WORKDIR /app

# numpy is used by the fixtures and by the deliverable's extraction math.
RUN pip install --no-cache-dir --disable-pip-version-check numpy

COPY files/ /app/
