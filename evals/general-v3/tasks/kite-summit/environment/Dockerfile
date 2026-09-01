FROM bench-base:python-3.12
RUN python3 -m pip install --no-cache-dir numpy >/dev/null 2>&1 && python3 -c "import numpy; print('numpy', numpy.__version__)"
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