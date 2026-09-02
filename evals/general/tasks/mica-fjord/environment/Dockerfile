# mica-fjord runtime image: vocabulary serialization against a frozen
# embedding matrix. Needs numpy for the .npy fixture.
FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir numpy==1.26.4

COPY files/ /app/

ENV PYTHONUNBUFFERED=1
