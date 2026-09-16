FROM bench-base:ubuntu-24.04

ENV DEBIAN_FRONTEND=noninteractive

# --- toolchains -------------------------------------------------------------
RUN apt-get update -qq && apt-get install -y -qq \
        golang-go \
        protobuf-compiler \
        curl \
        ca-certificates \
        git \
        make \
        python3-pip \
        jq \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages \
        grpcio==1.83.1 \
        grpcio-tools==1.83.1 \
        protobuf==7.36.1 \
        pytest==9.1.1

# --- go gRPC codegen plugins, installed into the trial user's go cache -------
USER ubuntu
ENV HOME=/home/ubuntu
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest && \
    go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# --- system-wide git safety (repo is built under /app at image build) --------
USER root
RUN git config --system --add safe.directory '*' && \
    git config --system user.email 'build@localhost' && \
    git config --system user.name 'build'
RUN cp /home/ubuntu/go/bin/protoc-gen-go /home/ubuntu/go/bin/protoc-gen-go-grpc /usr/local/bin/

# --- shipped files -----------------------------------------------------------
# /app and everything under it must end up owned by the trial user (uid 1000).
# Create the tree as that user in the first place: a chown -R in its own RUN
# layer would store a second copy of every file (Docker layers are
# copy-on-write), so the build below runs as the user that owns the result
# instead of correcting ownership afterwards.
USER ubuntu
WORKDIR /app
COPY --chown=ubuntu:ubuntu files/ /app/

# --- build the repo fixture (generator removes itself) -----------------------
# Runs as the owner of /app, so the compiled tree needs no separate chown.
RUN bash /app/gen_repo.sh

# --- warm the offline modget cache: scratch build of the SAME dependency set -
RUN mkdir -p /home/ubuntu/warm/proto && \
    cp /app/windlass-dispatch/go.mod /app/windlass-dispatch/go.sum /home/ubuntu/warm/ && \
    cp /app/windlass-dispatch/proto/dispatch.proto /home/ubuntu/warm/proto/ && \
    cd /home/ubuntu/warm && \
    export PATH="/usr/local/bin:$PATH" && \
    protoc -I proto --go_out=. --go-grpc_out=. proto/dispatch.proto && \
    printf 'package main\n\nimport (\n\tpb "windlass.dispatch.v2/dispatch.v2"\n\tlog "log"\n)\n\nfunc main() {\n\tlog.Printf("warm")\n\t_ = pb.DispatchReceipt{}\n}\n' > main.go && \
    go build -o warm-srv && \
    cd / && rm -rf /home/ubuntu/warm

USER root
CMD ["/bin/bash"]