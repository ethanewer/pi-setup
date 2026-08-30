FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# --- system layer: C toolchain, Python dev headers, OSMesa runtime library ---
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        build-essential \
        python3-dev \
        libosmesa6 \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

# --- python layer: numpy 2.x (makes the legacy numpy.distutils build helper
#     fail on this default interpreter), Cython, a modern setuptools, pytest ---
RUN python3 -m pip install -q --no-cache-dir \
        "numpy>=2.0" \
        "cython<3.1" \
        setuptools \
        pytest

# --- Miniconda base (baked; the target conda env is created at runtime) ------
RUN curl -fsSL \
        https://repo.anaconda.com/miniconda/Miniconda3-py312_24.9.2-0-Linux-x86_64.sh \
        -o /tmp/mc.sh \
    && bash /tmp/mc.sh -bfp /opt/miniconda3 \
    && rm -f /tmp/mc.sh \
    && /opt/miniconda3/bin/conda config --system --set auto_update_conda false

# --- fixtures: the source tree, the GL loader, the conda spec ---------------
COPY files/ /app/

# --- reproduce the DELIBERATELY BROKEN pristine state -------------------------
# 1) pip AND the bootstrap machinery (ensurepip) are knocked out of the
#    DEFAULT interpreter, so `python3 -m pip` orders "No module named pip" and
#    `python3 -m ensurepip` is also gone.  Only the official bootstrap script
#    (get-pip.py) can bring pip back.
RUN python3 - <<'PY'
import glob, os, shutil, sysconfig
pure = sysconfig.get_paths()['purelib']
stdlib = sysconfig.get_paths()['stdlib']
for d in ('pip', 'ensurepip'):
    shutil.rmtree(os.path.join(pure, d), ignore_errors=True)
for g in glob.glob(os.path.join(pure, 'pip-*.dist-info')):
    shutil.rmtree(g, ignore_errors=True)
shutil.rmtree(os.path.join(stdlib, 'ensurepip'), ignore_errors=True)
for b in ('pip', 'pip3', 'pip3.12'):
    p = os.path.join('/usr/local/bin', b)
    if os.path.exists(p):
        os.remove(p)
PY

# 2) the GL loader's fixed directory exists but is empty.
RUN mkdir -p /opt/hailshot/gl/lib

# 3) the packaged `hailshot` source is copied in but NOT installed; its legacy
#    numpy.distutils build helper cannot build under the default interpreter.

# smoke-check the intended broken state
RUN python3 - <<'PY'
import os, subprocess, sysconfig
broken = subprocess.run(['python3', '-m', 'pip', '--version'],
                        capture_output=True, text=True)
assert broken.returncode != 0, 'pip should be broken'
assert not os.path.exists(os.path.join(sysconfig.get_paths()['purelib'], 'pip'))
print('pristine broken state ready')
PY

WORKDIR /app