FROM bench-base:python-3.12

WORKDIR /app

# OCR engine + PDF + Pillow tooling for the classification pipeline.
RUN apt-get update \
 && apt-get install -y --no-install-recommends tesseract-ocr \
 && rm -rf /var/lib/apt/lists/*
RUN pip install --disable-pip-version-check pypdf pytesseract pillow

# Mixed batch of input documents (some PDFs, some raster images).
COPY files/inbox/ /app/inbox/