FROM bench-base:python-3.12

WORKDIR /app

# CPU build of torch keeps the image lean; the rest of the ML stack is what
# the pipeline needs: transformers for offline model/tokenizer loading, hub
# for the asset fetch, requests for the live leaderboard fetch, pyyaml for the
# harness task config, and langdetect for English-language detection.
RUN pip install --no-cache-dir \
        torch \
        --index-url https://download.pytorch.org/whl/cpu
RUN pip install --no-cache-dir \
        transformers \
        huggingface_hub \
        numpy \
        requests \
        pyyaml \
        langdetect

COPY files/ /app/
