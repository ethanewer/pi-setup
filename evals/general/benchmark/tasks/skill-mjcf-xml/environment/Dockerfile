FROM bench-base:python-3.12

WORKDIR /app

# A MuJoCo model (MJCF) that is well-formed XML but declares the wrong joint type.
RUN mkdir -p /app/model && cat > /app/model/pendulum.xml <<'EOF'
<mujoco model="pendulum">
  <default>
    <geom size="0.05"/>
  </default>
  <worldbody>
    <body name="slider" pos="0 0 0">
      <joint name="j0" type="hinge"/>
      <geom type="box" size="0.1 0.1 0.1"/>
    </body>
  </worldbody>
</mujoco>
EOF