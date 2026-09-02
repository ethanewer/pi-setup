FROM bench-base:python-3.12

# Motion-lab bench for myrtle-canyon. MuJoCo is deliberately NOT installed:
# the agent must install the pinned version offline from /app/wheelhouse.
# The pristine reference copy is kept at /opt/pristine for byte comparison.
WORKDIR /app

RUN pip download mujoco==3.2.4 -d /app/wheelhouse \
    && python3 -c "import os; fs=os.listdir('/app/wheelhouse'); \
assert any(f.startswith('mujoco-3.2.4') for f in fs), fs"

COPY files/ /app/
COPY files/ref-model.xml /opt/pristine/ref-model.xml
