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

# Robotics/vision/physicstack. opencv-python-headless supplies image reading and
# drawing without an X server; mujoco provides CPU physics (no GPU used).
RUN pip install --no-cache-dir \
        mujoco \
        opencv-python-headless \
        numpy \
        pillow

COPY files/ /app/