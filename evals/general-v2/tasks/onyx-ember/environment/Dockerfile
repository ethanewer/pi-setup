FROM bench-base:python-3.12

ENV DEBIAN_FRONTEND=noninteractive
ENV PIP_NO_CACHE_DIR=1

# ---- system toolchain (real work for rebuilding the extension + pip bootstrap)
RUN apt-get update -qq \
 && apt-get install -y -qq --no-install-recommends \
        build-essential \
        python3-dev \
        curl \
 && rm -rf /var/lib/apt/lists/*

# ---- python toolchain installed with the *working* pip, BEFORE pip is broken
#      (cython + setuptools are required to build the onyxprism extension later;
#      pytest runs the targeted async-fs unit suite; numpy is deliberately NOT
#      preinstalled - leaving it importable is part of the repair).
RUN pip install -q --no-warn-script-location \
        "cython>=3.0,<3.1" \
        "setuptools" \
        "pytest"

# ---- Miniconda baked in so the env-spec competency exercises conda itself,
#      not a parallel miniconda download. Pinned for a deterministic version.
RUN curl -fsSL \
        https://repo.anaconda.com/miniconda/Miniconda3-py312_24.9.2-0-Linux-x86_64.sh \
        -o /opt/miniconda-installer.sh \
 && bash /opt/miniconda-installer.sh -b -p /opt/miniconda \
 && rm -f /opt/miniconda-installer.sh \
 && /opt/miniconda/bin/conda config --system --set auto_update_conda false \
 && /opt/miniconda/bin/conda config --system --set channel_priority flexible

# ---- platform sources + fixtures (the *unrepaired* state is created below)
COPY files/app/ /app/

# 1) Default-interpreter package `onyxprism`: the factory image carries only a
#    broken stub in site-packages so `import onyxprism` raises until a working
#    build is compiled from /app/shelf/onyxprism and installed.
RUN /usr/local/bin/python3 - <<'PY'
import os, sysconfig
sp = sysconfig.get_paths()['purelib']
d = os.path.join(sp, 'onyxprism')
os.makedirs(d, exist_ok=True)
open(os.path.join(d, '__init__.py'), 'w').write(
    "'''broken stub shipped for a different CPython runtime'''\n"
    "raise ImportError('onyxprism native backend is not loadable by this "
    "interpreter: the shipped binding targets a different CPython ABI')\n")
PY

# 2) BREAK pip AFTER everything that needs it: remove the pip module and its
#    launcher so `python3 -m pip` fails until restored from the official
#    bootstrap script.
RUN /usr/local/bin/python3 -m pip uninstall -y -q pip

WORKDIR /app