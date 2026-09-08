FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
RUN pip install --no-cache-dir pillow==12.3.0 numpy==2.5.3 pytesseract==0.3.13 && \
    apt-get update && apt-get install -y --no-install-recommends tesseract-ocr && \
    rm -rf /var/lib/apt/lists/* && \
    tesseract --version | head -1
WORKDIR /app

COPY files/ /app/
