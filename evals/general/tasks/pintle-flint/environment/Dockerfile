# pintle-flint: scikit-image regionprops keeps its private cache populated even
# when caching is disabled (upstream issue scikit-image/scikit-image#7333).
#
# The image clones scikit-image SHALLOW at the PARENT commit (the real bug is
# in the working tree) and installs it in editable mode, so the code the agent
# imports is exactly the checked-out Python source and its edits take effect
# immediately. The project's own regression test for the bug is extracted from
# the FIX commit at build time into /opt/golden/ (upstream bytes never enter
# this repository). The fix commit is NOT reachable from the depth-1 working
# clone; extraction uses a throwaway clone that is deleted immediately.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=9107d523a899b8d3767630941ac28f438bf875d2
ARG FIX_SHA=119a89bc10801dd4c4557b007e97c79a06f9d24c

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build" \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends build-essential pkg-config \
 && rm -rf /var/lib/apt/lists/*

ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

# ---- dependencies, pinned exactly as the mining recipe (Cython<3.1 -> 3.0.12) --
RUN python3 -m pip install \
      'numpy==2.1.3' 'scipy==1.14.1' 'Cython==3.0.12' 'meson==1.12.0' \
      'meson-python==0.21.1' 'ninja==1.13.2' 'pythran==0.19.0' \
      'lazy-loader==0.5' 'packaging==26.3' 'networkx==3.6.1' \
      'pillow==12.3.0' 'imageio==2.37.4' 'tifffile==2026.9.9' \
      'matplotlib==3.11.2' 'pytest==9.1.1' 'pytest-cov==7.1.0' \
      'pytest-faulthandler==2.0.1' 'pytest-doctestplus==1.7.1' \
      'pytest-localserver==0.10.0' 'pooch==1.9.0' 'asv==0.6.6' \
      'numpydoc==1.10.0'

# ---- working clone: buggy parent commit, fix commit unreachable -------------
# A depth-1 clone of the default branch cannot contain the parent SHA, so fetch
# the parent by SHA, detach onto it and fail closed if upstream ever moves.
# HEAD is asserted against the pin; the fix commit must NOT be reachable.
RUN git clone --depth 1 https://github.com/scikit-image/scikit-image.git /app/src \
 && cd /app/src \
 && git fetch --depth 1 origin 9107d523a899b8d3767630941ac28f438bf875d2 \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && ! git cat-file -e "${FIX_SHA}^{commit}" \
 && git config --system --add safe.directory '/app/src'

# ---- extract the upstream regression test from the FIX commit ---------------
# Throwaway clone under /tmp, deleted immediately afterwards, so the fix object
# never exists inside /app/src/.git and never enters this task tree.
RUN git init -q /tmp/fixsrc \
 && cd /tmp/fixsrc \
 && git remote add origin https://github.com/scikit-image/scikit-image.git \
 && git fetch --depth 1 origin 119a89bc10801dd4c4557b007e97c79a06f9d24c \
 && mkdir -p /opt/golden \
 && git show 119a89bc10801dd4c4557b007e97c79a06f9d24c:skimage/measure/tests/test_regionprops.py \
      > /opt/golden/test_regionprops.py \
 && test -s /opt/golden/test_regionprops.py \
 && grep -q "def test_disabled_cache_is_empty" /opt/golden/test_regionprops.py \
 && python3 -c "import ast; ast.parse(open('/opt/golden/test_regionprops.py').read())" \
 && chmod 444 /opt/golden/test_regionprops.py \
 && cd / \
 && rm -rf /tmp/fixsrc

# Belt: prove the fix commit is NOT reachable from the trial clone, both before
# and after the editable install.
RUN cd /app/src \
 && if git cat-file -e 119a89bc10801dd4c4557b007e97c79a06f9d24c^{commit} 2>/dev/null; then \
      echo "ERROR: fix commit is reachable from /app/src"; exit 1; \
    fi

# ---- editable install, warm every cache at build time (trial is offline) ----
RUN cd /app/src \
 && python3 -m pip install -e . --no-build-isolation --config-settings=setup-args=-Dcpp_std=c++17 \
 && pip list 2>/dev/null | grep -i scikit \
 && ! git cat-file -e 119a89bc10801dd4c4557b007e97c79a06f9d24c^{commit}

# Baseline sanity at the pinned parent: the project's own regionprops suite must
# be green here even with the bug present (the bug only shows through the cache
# retention symptom and the fix-commit regression test).
WORKDIR /app/src
RUN python3 -m pytest skimage/measure/tests/test_regionprops.py -q -p no:cacheprovider 2>&1 | tail -2

WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app

CMD ["/bin/bash"]