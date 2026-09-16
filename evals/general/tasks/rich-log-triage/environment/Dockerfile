FROM bench-base:python-3.12
WORKDIR /app
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 PYTHONHASHSEED=0 TERM=dumb NO_COLOR=1 \
    OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1 MKL_NUM_THREADS=1 \
    VECLIB_MAXIMUM_THREADS=1 NUMEXPR_NUM_THREADS=1 BLIS_NUM_THREADS=1 \
    RAYON_NUM_THREADS=1
RUN python -m pip install --no-cache-dir \
    'poetry-core==2.2.1' 'markdown-it-py==4.2.0' 'mdurl==0.1.2' 'Pygments==2.21.0' \
    && python -m pip install --no-cache-dir --no-deps --no-build-isolation \
    'https://github.com/Textualize/rich/archive/9d8f9a372cc5916fd4781fec207ced7ddac2f08f.tar.gz'
COPY files/source /app/source
