FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --disable-pip-version-check pillow numpy

COPY files/img_a.png /app/img_a.png
COPY files/img_b.png /app/img_b.png