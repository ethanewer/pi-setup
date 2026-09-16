ARG UPSTREAM_SHA=16fa855354eb7bcabd3fe10993841e03b1382692

FROM bench-base:python-3.12

ARG UPSTREAM_SHA=16fa855354eb7bcabd3fe10993841e03b1382692

# Real upstream tree, pinned to the immutable 40-hex commit. Shallow: the
# full sympy history is hundreds of MB and this task never needs it.
RUN git clone --depth 1 --branch sympy-1.14.0 \
        https://github.com/sympy/sympy.git /app/src \
 && cd /app/src \
 && test "$(git rev-parse HEAD)" = "$UPSTREAM_SHA" \
 && git config --system --add safe.directory '*'

# Sympy's own test runner needs mpmath (runtime dep) and pytest/hypothesis
# (its conftest refuses to run without hypothesis). Exact pins resolved
# against the base image's interpreter.
RUN pip install --no-cache-dir mpmath==1.4.1 hypothesis==6.112.0 pytest==8.3.5

WORKDIR /app

COPY files/ /app/

# The authored regression: a one-line defect in the radix-2 FFT butterfly
# (see files/regression.patch). Apply it, then remove the git metadata so
# no diff or history archaeology can reveal the intro, and guarantee write
# access for whatever uid (root or 1000) the trial runs as.
RUN git -C /app/src apply /app/regression.patch \
 && rm -rf /app/src/.git \
 && rm -f /app/regression.patch \
 && chmod -R a+rwX /app \
 && echo "build-ok"