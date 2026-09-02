FROM bench-base:python-3.12

RUN pip install --no-cache-dir \
    numpy \
    scipy \
    "astropy>=6.0"

WORKDIR /app
COPY files/ /app/