FROM bench-base:python-3.12

WORKDIR /app

# Fixtures: local wheel index + the probe tool + the python manifest file + the
# npm manifest that must be edited. The venv itself is assembled below.
COPY files/ /app/

# Assemble the DELIBERATELY BROKEN hedge venv.
#   * it bundles lotusfields 0.7.0 (too old to accept the dtype_backend=
#     keyword) and coreclutch 0.5.0,
#   * and its pip installation is broken on purpose: the pip module and every
#     pip binary are removed from the venv, so `python -m pip` reports
#     "No module named pip". ensurepip is warmly intact so the interpreter can
#     be brought back to a working state.
RUN python3 -m venv /app/env/.venv && \
    /app/env/.venv/bin/python -m pip install --no-cache-dir --no-index \
        --find-links /app/garden_wheel \
        "lotusfields==0.7.0" "coreclutch==0.5.0" && \
    rm -rf \
        /app/env/.venv/bin/pip \
        /app/env/.venv/bin/pip3 \
        /app/env/.venv/bin/pip3.12 \
        /app/env/.venv/lib/python3.12/site-packages/pip \
        /app/env/.venv/lib/python3.12/site-packages/pip-*.dist-info && \
    printf '\n# delivered broken state: pip removed, lotusfields==0.7.0\n' >> /app/env/.venv/pyvenv.cfg

# Smoke: the venv must be broken (pip absent) but the interpreter importable.
RUN /app/env/.venv/bin/python -c "import sys; assert sys.version_info[:2]==(3,12)" && \
    ( /app/env/.venv/bin/python -m pip --version 2>/dev/null \
        && echo 'pip present UNEXPECTED' || echo 'pip absent as intended' ) && \
    /app/env/.venv/bin/python -c "from lotusfields import __version__; print('bundled lotusfields', __version__)"