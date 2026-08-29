#!/usr/bin/env python3
"""AtlasRidge control-plane gateway.

Creates a live gRPC AtlasGateway service (persistent key/value store plus a
cluster status endpoint) and, in launch mode, also starts a background mlflow
tracking server on 127.0.0.1:8080.

CLI:
    python3 /app/serve.py            # launch mode: mlflow + gateway on config.port
    python3 /app/serve.py launch     # same
    python3 /app/serve.py <PORT>     # gRPC-only mode, gateway on 0.0.0.0:<PORT>

Env:
    ATLAS_CONFIG          config file path (default /app/config.json)
    ATLAS_MLFLOW_PORT     mlflow tracking port (default 8080)
"""
import json
import os
import subprocess
import sys
import threading
import time
import urllib.request
from concurrent import futures

import grpc
import atlas_pb2 as pb
import atlas_pb2_grpc as pbg

MLFLOW_HOST = "127.0.0.1"
_KEEP = []


def load_config():
    path = os.environ.get("ATLAS_CONFIG", "/app/config.json")
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


class KvStore:
    """Persistent JSON key/value store with atomic tmp+rename writes."""

    def __init__(self, path, lock):
        self.path = path
        self.lock = lock
        self.data = {}
        if os.path.exists(path):
            try:
                with open(path, "r", encoding="utf-8") as f:
                    blob = json.load(f)
                if isinstance(blob, dict):
                    self.data = dict(blob.get("kv", {}) or {})
            except Exception:
                self.data = {}

    def put(self, key, value):
        with self.lock:
            self.data[key] = str(value)
            self._flush()

    def get(self, key):
        with self.lock:
            if key not in self.data:
                raise KeyError(key)
            return self.data[key]

    def count(self):
        with self.lock:
            return len(self.data)

    def _flush(self):
        tmp = self.path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump({"kv": self.data}, f, sort_keys=True)
        os.replace(tmp, self.path)


class AtlasGateway(pbg.AtlasGatewayServicer):
    def __init__(self, cfg, store):
        self.cfg = cfg
        self.store = store

    def Put(self, request, context):
        if not request.key:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, "empty key")
        self.store.put(request.key, request.value)
        return pb.PutReply(ok=True)

    def Get(self, request, context):
        try:
            return pb.ValueMsg(value=self.store.get(request.key))
        except KeyError:
            context.abort(
                grpc.StatusCode.NOT_FOUND, "key absent: %r" % (request.key,)
            )

    def Status(self, request, context):
        return pb.StatusInfo(
            healthy=True,
            cluster=self.cfg.get("cluster", "atlas"),
            nodes=list(self.cfg.get("nodes", [])),
            capacity_bytes=int(self.cfg.get("capacity_bytes", 0)),
            objects=self.store.count(),
            detail=("probe=%s online" % (request.probe_id or "unknown")).strip(),
        )


def build_server(cfg, port):
    lock = threading.Lock()
    store_path = cfg.get("store_path", "/tmp/atlas_store/kv_store.json")
    parent = os.path.dirname(os.path.abspath(store_path))
    if parent:
        os.makedirs(parent, exist_ok=True)
    store = KvStore(store_path, lock)
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=16))
    pbg.add_AtlasGatewayServicer_to_server(AtlasGateway(cfg, store), server)
    server.add_insecure_port("0.0.0.0:%d" % int(port))
    server.start()
    return server, store


def _host_healthy(host, port):
    try:
        with urllib.request.urlopen(
            "http://%s:%d/health" % (host, port), timeout=2
        ) as r:
            return r.status == 200
    except Exception:
        return False


def start_mlflow(cfg):
    portal = int(os.environ.get("ATLAS_MLFLOW_PORT", "8080"))
    store_dir = cfg.get("mlflow_store", "/tmp/mlflow")
    os.makedirs(store_dir, exist_ok=True)
    db = os.path.join(store_dir, "mlflow.db")
    cmd = [
        "mlflow", "server",
        "--host", MLFLOW_HOST,
        "--port", str(portal),
        "--backend-store-uri", "sqlite:///" + db,
        "--default-artifact-root", store_dir,
    ]
    env = dict(os.environ)
    env.setdefault("MLFLOW_ALLOW_FILE_STORE", "true")
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.STDOUT,
        env=env,
    )
    _KEEP.append(proc)  # hold a reference so it is not GC'd/reaped
    return proc


def _launch_ml_thread(cfg):
    try:
        start_mlflow(cfg)
    except Exception:
        pass


def main(argv):
    args = [a for a in argv if a]
    cfg = load_config()
    launch = (not args) or args[0].lower() in ("launch", "all")
    if launch:
        # Bring mlfall up in the background WITHOUT delaying the gRPC gateway
        # (the verifier polls its /health endpoint itself).
        threading.Thread(target=_launch_ml_thread, args=(cfg,), daemon=True).start()
        port = int(cfg.get("port", 5000))
    else:
        port = int(args[0])
    server, _ = build_server(cfg, port)
    try:
        while True:
            time.sleep(3600)
    except KeyboardInterrupt:
        server.stop(0)
        raise SystemExit(0)


if __name__ == "__main__":
    main(sys.argv[1:])