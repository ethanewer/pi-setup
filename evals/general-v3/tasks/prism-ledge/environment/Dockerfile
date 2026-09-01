FROM bench-base:python-3.12

WORKDIR /app

# System libs: PNG decoding in C (libpng), tesseract for OCR, python dev headers
# only needed for C compilation of /app/cdecode (gcc + libpng-dev + pkg-config).
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc \
        libc6-dev \
        pkg-config \
        libpng-dev \
        tesseract-ocr \
        make \
    && rm -rf /var/lib/apt/lists/*

# Python ML/vision stack (torch is pulled as the CPU wheel). pytesseract is the
# OCR binding; the tesseract binary is installed above.
RUN pip install --no-cache-dir \
        torch \
        opencv-python-headless \
        numpy \
        timm \
        pytesseract

COPY files/ /app/
