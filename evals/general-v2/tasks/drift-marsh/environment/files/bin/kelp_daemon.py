#!/usr/bin/env python3
"""Kelpline single-node store daemon (shipped program; do not modify).

Usage: kelp_daemon.py <namenode|datanode>

Reads the two Kelpline property files from the configuration directory
(honouring KELP_CONF_DIR, default /app/conf):

  core.properties:  kelpline.node.address, kelpline.rpc.port
  site.properties:  kelpline.role.master (namenode),
                    kelpline.role.worker (datanode),
                    kelpline.replication.factor (1)

The namenode role requires kelpline.role.master == "namenode" and binds
kelpline.node.address:kelpline.rpc.port. The datanode role requires
kelpline.role.worker == "datanode" and kelpline.replication.factor == 1 and
binds kelpline.node.address:kelpline.rpc.port + 1.

On success it writes <role>.pid and <role>.ready into the run directory
(honouring KELP_RUN_DIR, default /app/run) and then idles forever with the
socket bound. On any misconfiguration it prints a diagnostic to stderr and
exits non-zero WITHOUT binding.
"""
import os
import socket
import sys
import time

CONF_DIR = os.environ.get("KELP_CONF_DIR") or "/app/conf"
RUN_DIR = os.environ.get("KELP_RUN_DIR") or "/app/run"


def fail(msg):
    sys.stderr.write("kelp-daemon: %s\n" % msg)
    sys.stderr.flush()
    sys.exit(2)


def load_props(path):
    props = {}
    with open(path, "r", encoding="utf-8") as fh:
        for raw in fh:
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("!"):
                continue
            if "=" not in line:
                continue
            key, _, val = line.partition("=")
            props[key.strip()] = val.strip()
    return props


def main():
    if len(sys.argv) != 2:
        fail("usage: kelp_daemon.py <namenode|datanode>")
    role = sys.argv[1]

    try:
        core = load_props(os.path.join(CONF_DIR, "core.properties"))
        site = load_props(os.path.join(CONF_DIR, "site.properties"))
    except OSError as exc:
        fail("unreadable Kelpline config in %s: %r" % (CONF_DIR, exc))

    addr = core.get("kelpline.node.address", "")
    port_raw = core.get("kelpline.rpc.port", "")
    if not addr:
        fail("kelpline.node.address is empty or missing")
    try:
        base_port = int(port_raw)
    except ValueError:
        fail("kelpline.rpc.port is not an integer: %r" % port_raw)

    if role == "namenode":
        binding = site.get("kelpline.role.master", "")
        if binding != "namenode":
            fail("kelpline.role.master must be 'namenode' for the namenode "
                 "role (got %r)" % binding)
        port = base_port
    elif role == "datanode":
        binding = site.get("kelpline.role.worker", "")
        if binding != "datanode":
            fail("kelpline.role.worker must be 'datanode' for the datanode "
                 "role (got %r)" % binding)
        repl_raw = site.get("kelpline.replication.factor", "")
        try:
            if int(repl_raw) != 1:
                fail("kelpline.replication.factor must be 1 for single-node "
                     "operation (got %r)" % repl_raw)
        except ValueError:
            fail("kelpline.replication.factor is not an integer: %r" % repl_raw)
        port = base_port + 1
    else:
        fail("unknown role %r" % role)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind((addr, port))
    except OSError as exc:
        fail("bind failed on %s:%d (%r)" % (addr, port, exc))
    sock.listen(16)

    os.makedirs(RUN_DIR, exist_ok=True)
    with open(os.path.join(RUN_DIR, role + ".pid"), "w") as fh:
        fh.write(str(os.getpid()) + "\n")
    with open(os.path.join(RUN_DIR, role + ".ready"), "w") as fh:
        fh.write("ready role=%s addr=%s port=%d\n" % (role, addr, port))
    sys.stdout.write("KELP %s READY addr=%s port=%d\n" % (role, addr, port))
    sys.stdout.flush()

    while True:
        time.sleep(60)


if __name__ == "__main__":
    main()
