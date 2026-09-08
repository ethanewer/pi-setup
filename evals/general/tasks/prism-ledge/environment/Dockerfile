FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

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
        torch==2.14.0 \
        opencv-python-headless==5.0.0.93 \
        numpy==2.5.3 \
        timm==1.0.29 \
        pytesseract==0.3.13

COPY files/ /app/
