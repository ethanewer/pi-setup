FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- system layer: compilers, OSMesa runtime library, R stack, R analysis package
RUN apt-get update -qq \
    && apt-get install -y -qq --no-install-recommends \
        build-essential \
        python3-dev \
        libosmesa6 \
        r-base-core \
        r-cran-irkernel \
        r-cran-jsonlite \
    && rm -rf /var/lib/apt/lists/*

# ---- python layer: numpy 2.x, cython, pytest, jupyter tooling
RUN pip install -q \
        "numpy>=2.0" \
        "cython<3.1" \
        setuptools \
        pytest \
        jupyter \
        ipykernel

# ---- platform sources + fixtures (the *unrepaired* state is created below)
COPY files/ /app/

# 1) kether: a broken stub is already in the default interpreter's site-packages,
#    so `import kether` fails until a working build is installed.
RUN python3 - <<'PY'
import os, sysconfig
sp = sysconfig.get_paths()['purelib']
d = os.path.join(sp, 'kether')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').write(
    "'''broken stub left from a different runtime'''\n"
    "raise ImportError('kether native binding unavailable for this interpreter')\n")
PY

# 2) the edited package `spect` is NOT yet installed: the old buggy build is
#    what lives in site-packages, so its target suite fails until the repair.
RUN python3 - <<'PY'
import os, sysconfig
sp = sysconfig.get_paths()['purelib']
d = os.path.join(sp, 'spect')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').write(
    "import hashlib\n"
    "def prefix_digest(text):\n"
    "    return hashlib.md5(str(text).encode()).hexdigest()[:6]\n"
    "__version__ = '0.3.0-unedited'\n")
PY

# 3) the OSMesa loader's fixed location exists but is empty.
RUN mkdir -p /opt/osp/gl/lib

# Everything above deliberately reproduces the broken pristine state; nothing
# is fixed here so a fresh container without the repair passes no check.
WORKDIR /app