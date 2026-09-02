FROM bench-base:python-3.12
RUN pip install --no-cache-dir numpy opencv-python-headless pillow pytesseract scipy && \
    apt-get update && apt-get install -y --no-install-recommends tesseract-ocr && \
    rm -rf /var/lib/apt/lists/* && \
    tesseract --version | head -1
WORKDIR /app
COPY files/ /app/