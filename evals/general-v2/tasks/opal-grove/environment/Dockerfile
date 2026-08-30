# opal-grove runtime image: prototxt solver + network definitions for the
# frozen cafelite trainer.
FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy==1.26.4

COPY files/ /app/

ENV PYTHONUNBUFFERED=1
