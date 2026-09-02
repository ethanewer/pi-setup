FROM bench-base:python-3.12

WORKDIR /app

# Local (offline) pip index that provision.sh uses for the pinned packages.
COPY files/ridge-index /opt/ridge-index

# gRPC service definition the server venv turns into Python bindings.
COPY files/chain.proto /app/chain.proto

# System-wide toolchain inherited by the venvs via --system-site-packages:
# the Jupyter notebook server, and the gRPC runtimes/tools.
RUN pip install --quiet --no-cache-dir --no-warn-script-location \
        notebook \
        grpcio \
        grpcio-tools \
        protobuf

# The OLD bundled data-frame library (1.4.0) is installed system-wide on
# purpose: /app/venvs/analytics inherits it, and its `Table.groupby` does NOT
# accept the `collapse=` keyword. The analytics environment must upgrade it to
# >= 2.0.0 so `collapse=` becomes available.
RUN pip install --quiet --no-index --find-links=/opt/ridge-index 'ridgedf==1.4.0'

# Confirm the inherited toolchain is present before the agent starts.
RUN python3 -c "import grpc, google.protobuf; print('grpc ok')" \
 && python3 -c "import ridgedf; print('bundled ridgedf', ridgedf.__version__)" \
 && (python3 -m jupyter --version >/dev/null 2>&1 || python3 -c "import notebook; print('notebook ok')")
