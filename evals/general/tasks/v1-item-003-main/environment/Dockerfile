FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir pytest

COPY files/ /app/

RUN mkdir -p /app/tests