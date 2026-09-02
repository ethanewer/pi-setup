FROM bench-base:python-3.12

WORKDIR /app

# OCR engine, PDF rasteriser and the Python image/ML stack used by the
# document-intelligence pipeline. All pure-CPU; no GPU/X/systemd.
RUN apt-get update && apt-get install -y --no-install-recommends \
        tesseract-ocr \
        poppler-utils \
        fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

RUN pip install --no-cache-dir \
        pillow \
        numpy \
        scikit-learn

COPY files/ /app/