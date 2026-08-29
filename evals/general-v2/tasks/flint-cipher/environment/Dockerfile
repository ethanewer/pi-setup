FROM bench-base:python-3.12

WORKDIR /app

COPY files/ /app/

RUN pip install --no-cache-dir \
        "numpy" \
        "scikit-learn" \
        "tokenizers" \
    && python3 -c "import numpy, sklearn, tokenizers; print('deps ok', numpy.__version__)"