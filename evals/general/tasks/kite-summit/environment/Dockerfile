FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
RUN python3 -m pip install --no-cache-dir numpy==2.5.3 >/dev/null 2>&1 && python3 -c "import numpy; print('numpy', numpy.__version__)"
WORKDIR /app
COPY files/ /app/
# Record the pristine global site-packages size as the footprint baseline.
RUN python3 - <<'PY'
import os
import site
d = site.getsitepackages()[0]
n = 0
for r, _, fs in os.walk(d):
    for f in fs:
        try:
            n += os.path.getsize(os.path.join(r, f))
        except OSError:
            pass
open('/opt/site-baseline.txt', 'w').write(str(n))
print('baseline bytes:', n)
PY