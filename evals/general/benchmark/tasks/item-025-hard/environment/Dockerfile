FROM bench-base:python-3.12

WORKDIR /app

# OCR engine + a sans font for deterministic document rendering
RUN apt-get update && apt-get install -y tesseract-ocr tesseract-ocr-eng fonts-liberation && rm -rf /var/lib/apt/lists/*

# Python imaging / OCR / PDF libraries
RUN pip install -q --break-system-packages pillow pymupdf pytesseract

# Build the deterministic inbox documents (then delete the generator so it is
# not part of the shipped container).
COPY generate_docs.py /app/generate_docs.py
RUN python3 /app/generate_docs.py && rm -f /app/generate_docs.py

COPY files/evaluate.py /app/evaluate.py

WORKDIR /app