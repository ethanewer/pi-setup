FROM bench-base:python-3.12

WORKDIR /app

# Robotics/vision/physicstack. opencv-python-headless supplies image reading and
# drawing without an X server; mujoco provides CPU physics (no GPU used).
RUN pip install --no-cache-dir \
        mujoco \
        opencv-python-headless \
        numpy \
        pillow

COPY files/ /app/