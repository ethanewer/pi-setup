FROM bench-base:python-3.12

WORKDIR /app

COPY files/freezegun_base /app/freezegun_base
COPY files/reproduce.py /app/reproduce.py

RUN pip install --no-cache-dir python-dateutil==2.9.0.post0 six==1.17.0

ENV PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
