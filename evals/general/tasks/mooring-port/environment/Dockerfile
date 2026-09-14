# mooring-port: pylint-dev/pylint — fatal internal error on empty-tuple
# type-argument subscripts (upstream issue #11357).
#
# The image clones pylint via `git init` + a single `git fetch --depth 1 origin
# <parent-sha>` and detaches there, so the ONLY commit object in /app/src/.git
# is the buggy parent commit 92b631fac22e503e9520fb5280929499b6787093 (HEAD is
# asserted to equal the pin, so the build fails closed if upstream moves).
# The fix commit 5e00da601a4c14f8321494db4dcdb4a9e42e92d7 is never fetched into
# /app/src; it is fetched only into a throwaway clone under /tmp (deleted
# afterwards) to extract the project's own regression test
# (tests/functional/ext/typing/unnecessary_default_type_args.*, fix-commit
# version carrying the Generator[()]/AsyncGenerator[()] cases) into
# /opt/golden/ext/typing/. Neither pylint nor any of its dependencies is a
# Terminal-Bench 2.1 source repository (checked against
# specs/tb21_source_repositories.json).
#
# pylint is installed editable from the checked-out tree together with the
# project's own test dependencies pinned exactly (astroid==4.2.0b5 per
# requirements_test_min.txt, pytest 8.4.1, ...), so the trial needs no network.
# A pristine copy of the parent's pylint/extensions/typing.py is kept at
# /opt/pristine_typing.py so the verifier can run the agent's reproduction
# against the pre-fix code path by temporarily swapping the file back.
# Ownership is set with a chmod in the same RUN that produced the tree, so no
# copy-on-write layer duplication is created.
FROM bench-base:python-3.12

ARG UPSTREAM_SHA=92b631fac22e503e9520fb5280929499b6787093
ARG FIX_SHA=5e00da601a4c14f8321494db4dcdb4a9e42e92d7

RUN git config --system --add safe.directory '*' \
 && git config --system user.email "build@localhost" \
 && git config --system user.name "build"

# ---- working clone: buggy parent commit only, fix commit unreachable -------
RUN git init -q /app/src \
 && git -C /app/src remote add origin https://github.com/pylint-dev/pylint.git \
 && git -C /app/src fetch --depth 1 origin ${UPSTREAM_SHA} \
 && git -C /app/src checkout -q --detach FETCH_HEAD \
 && test "$(git -C /app/src rev-parse HEAD)" = "${UPSTREAM_SHA}" \
 && ! git -C /app/src cat-file -e "${FIX_SHA}^{commit}" \
 && test "$(git -C /app/src rev-list --all --count)" = "1" \
 && cp /app/src/pylint/extensions/typing.py /opt/pristine_typing.py \
 && chmod -R a+rwX /app/src /opt/pristine_typing.py

# ---- extract the upstream regression test from the FIX commit ----------------
# Throwaway clone, deleted afterwards: the fix commit never exists inside
# /app/src/.git. Upstream bytes never enter this repository either; the golden
# files live only in the image at /opt/golden/ext/typing/.
RUN git init -q /tmp/fixsrc \
 && git -C /tmp/fixsrc remote add origin https://github.com/pylint-dev/pylint.git \
 && git -C /tmp/fixsrc fetch --depth 1 origin ${FIX_SHA} \
 && mkdir -p /opt/golden/ext/typing \
 && for f in unnecessary_default_type_args.py unnecessary_default_type_args.txt unnecessary_default_type_args.rc unnecessary_default_type_args.313.txt; do \
      git -C /tmp/fixsrc show ${FIX_SHA}:tests/functional/ext/typing/$f > /opt/golden/ext/typing/$f || exit 1; \
    done \
 && cd / && rm -rf /tmp/fixsrc \
 && test -s /opt/golden/ext/typing/unnecessary_default_type_args.py \
 && grep -q "e1: ca.Generator\[()\]" /opt/golden/ext/typing/unnecessary_default_type_args.py \
 && grep -q "load-plugins=pylint.extensions.typing" /opt/golden/ext/typing/unnecessary_default_type_args.rc \
 && chmod -R a+rX /opt/golden

# ---- project + pinned test dependencies (the trial has no network) -----------
# Every version pinned explicitly; all resolvable on bench-base:python-3.12
# (Python 3.12.13). Verified in a throwaway probe build before authoring.
RUN python3 -m pip install --no-cache-dir -e /app/src
RUN python3 -m pip install --no-cache-dir -U \
      astroid==4.2.0b5 typing-extensions==4.15.0 py==1.11.0 pytest==8.4.1 \
      pytest-benchmark==5.1.0 pytest-timeout==2.4.0 towncrier==25.8.0 requests==2.34.2 \
      pytest-cov==6.2.1 pytest-xdist==3.8.0 six==1.17.0 coverage==7.10.0

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    OMP_NUM_THREADS=1

WORKDIR /app
COPY files/ /app/

RUN chmod -R a+rwX /app && mkdir -p /root/.cache/pylint
CMD ["/bin/bash"]