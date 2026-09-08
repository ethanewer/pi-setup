# zephyr-bridge task image: tokenizer + 300-dim embeddings + fasttext-style
# classifier + metrics + vocab-dataclass shipping bundle.  CPU-only.
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

RUN pip install --no-cache-dir \
    numpy==1.26.4 \
    scipy==1.18.1 \
    scikit-learn==1.9.0 \
    gensim==4.3.3

# shared loader + corpus generator fixtures
COPY files/ /app/

# ship the labeled review corpus for the agent
RUN python3 /app/gen_corpus.py --out /app/data/reviews.tsv --seed 11 --count 2600 --edge 0

ENV PYTHONUNBUFFERED=1

CMD ["/bin/bash"]