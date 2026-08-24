FROM bench-base:python-3.12

WORKDIR /app

RUN pip install --no-cache-dir mujoco

# A minimal MuJoCo model: a single free body with a sphere geom.
RUN mkdir -p /app/model && cat > /app/model/box.xml <<'EOF'
<mujoco>
  <default>
    <geom size="0.05" type="sphere"/>
  </default>
  <worldbody>
    <body name="b" pos="0 0 0">
      <freejoint/>
      <geom type="sphere"/>
    </body>
  </worldbody>
</mujoco>
EOF