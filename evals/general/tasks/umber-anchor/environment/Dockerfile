FROM bench-base:python-3.12

# [environment] declares cpus = 1, which Docker enforces as a CFS
# quota and not as a CPU-affinity mask: the process still sees every
# host core, so thread pools sized from the core count oversubscribe the
# quota badly. Pin them to the declared budget.
ENV OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1
WORKDIR /app

# No systemd / GPU / X. zsh is the only heavy apt addition.
RUN apt-get update -qq && apt-get install -y -qq --no-install-recommends zsh >/dev/null \
    && rm -rf /var/lib/apt/lists/*

# A tiny self-authored zsh framework: a loader plus a small library of
# themes and plugins. Installed so the agent must wire it up but files exist.
COPY files/zframe/ /app/zframe/

# A deliberately BROKEN environment spec (numpy 2.5.0 vs scipy 1.12.0 clash).
# The agent must edit /app/environment.lock so pip can resolve one consistent set.
COPY files/environment.lock /app/environment.lock

# Make zsh available on PATH regardless of how the environment is entered.
RUN ln -sf /bin/zsh /usr/local/bin/zsh || true