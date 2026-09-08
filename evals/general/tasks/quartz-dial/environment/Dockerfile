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

# CPU build of torch keeps the image lean; the rest of the ML stack is what
# the pipeline needs: transformers for offline model/tokenizer loading, hub
# for the asset fetch, requests for the live leaderboard fetch, pyyaml for the
# harness task config, and langdetect for English-language detection.
RUN pip install --no-cache-dir \
        torch==2.14.0+cpu \
        --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir \
        transformers==5.16.1 \
        huggingface_hub==1.30.0 \
        numpy==2.5.3 \
        requests==2.34.2 \
        pyyaml==6.0.3 \
        langdetect==1.0.9

COPY files/ /app/
