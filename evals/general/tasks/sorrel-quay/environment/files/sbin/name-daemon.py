#!/usr/bin/env python3
"""Sorrel Quay single-node cluster name-daemon emulator.

Usage: name-daemon.py <role>   (role: namenode | datanode)

Reads the site configuration from /app/conf/core-site.xml and
/app/conf/hdfs-site.xml (Hadoop-style <property><name>/<value> XML), binds the
configured endpoints, and serves a tiny one-line request/response protocol:

  namenode (rpc socket = fs.defaultFS, plus web UI socket =
  dfs.namenode.http-address):
      PING         -> PONG namenode-1
      REPLICATION  -> replication=<dfs.replication>
      DEFAULTFS    -> defaultfs=<fs.defaultFS>
      HTTPADDR     -> httpaddr=<dfs.namenode.http-address>

  datanode (socket = dfs.datanode.address):
      PING         -> PONG datanode-1
      DATADIR      -> datadir=<dfs.datanode.data.dir>

Exits non-zero if the site configuration is missing, malformed, or missing any
required property (a miswritten config string keeps the role from coming up).
"""
import os
import socket
import sys
import time
import xml.etree.ElementTree as ET

CONF_DIR = "/app/conf"
RUN_DIR = "/app/run"
CORE_SITE = os.path.join(CONF_DIR, "core-site.xml")
HDFS_SITE = os.path.join(CONF_DIR, "hdfs-site.xml")


def load_props():
    props = {}
    for path in (CORE_SITE, HDFS_SITE):
        if not os.path.isfile(path):
            sys.stderr.write("CONFIG INCOMPLETE: missing %s\n" % path)
            sys.exit(2)
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as exc:
            sys.stderr.write("CONFIG INCOMPLETE: %s is not valid XML: %s\n" % (path, exc))
            sys.exit(2)
        for prop in root.findall("property"):
            name = (prop.findtext("name") or "").strip()
            value = (prop.findtext("value") or "").strip()
            if name:
                props[name] = value
    return props


def require(props, key):
    value = props.get(key, "")
    if not value:
        sys.stderr.write("CONFIG INCOMPLETE: property %s is not set\n" % key)
        sys.exit(2)
    return value


def parse_hdfs_uri(uri):
    # hdfs://host:port
    if not uri.startswith("hdfs://"):
        sys.stderr.write("CONFIG INCOMPLETE: fs.defaultFS %r is not an hdfs:// URI\n" % uri)
        sys.exit(2)
    rest = uri[len("hdfs://"):]
    host, sep, port_s = rest.rpartition(":")
    if not sep or not host or not port_s.isdigit():
        sys.stderr.write("CONFIG INCOMPLETE: fs.defaultFS %r has no host:port\n" % uri)
        sys.exit(2)
    return host, int(port_s)


def parse_hostport(value):
    host, sep, port_s = value.rpartition(":")
    if not sep or not host or not port_s.isdigit():
        sys.stderr.write("CONFIG INCOMPLETE: %r is not host:port\n" % value)
        sys.exit(2)
    return host, int(port_s)


def bind(host, port, label):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        srv.bind((host, port))
    except OSError as exc:
        sys.stderr.write("cannot bind %s on %s:%d: %s\n" % (label, host, port, exc))
        sys.exit(3)
    srv.listen(16)
    return srv


def handle(conn, handlers):
    conn.settimeout(5)
    try:
        data = conn.recv(256).decode("utf-8", "replace").strip()
        reply = handlers.get(data)
        if reply is not None:
            conn.sendall((reply + "\n").encode("utf-8"))
    except OSError:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("namenode", "datanode"):
        sys.stderr.write("usage: name-daemon.py <namenode|datanode>\n")
        sys.exit(2)
    role = sys.argv[1]
    props = load_props()
    os.makedirs(RUN_DIR, exist_ok=True)

    if role == "namenode":
        defaultfs = require(props, "fs.defaultFS")
        host, rpc_port = parse_hdfs_uri(defaultfs)
        http_addr = require(props, "dfs.namenode.http-address")
        hhost, hport = parse_hostport(http_addr)
        replication = require(props, "dfs.replication")
        if not replication.isdigit():
            sys.stderr.write("CONFIG INCOMPLETE: dfs.replication %r is not an integer\n" % replication)
            sys.exit(2)
        handlers = {
            "PING": "PONG namenode-1",
            "REPLICATION": "replication=%s" % replication,
            "DEFAULTFS": "defaultfs=%s" % defaultfs,
            "HTTPADDR": "httpaddr=%s" % http_addr,
        }
        rpc_srv = bind(host, rpc_port, "namenode rpc")
        http_srv = bind(hhost, hport, "namenode web UI")
        with open(os.path.join(RUN_DIR, "namenode.ready"), "w") as fh:
            fh.write(str(os.getpid()))
        while True:
            for srv in (rpc_srv, http_srv):
                try:
                    srv.settimeout(0.5)
                    conn, _ = srv.accept()
                except socket.timeout:
                    continue
                srv.settimeout(None)
                handle(conn, handlers)
    else:
        dn_addr = require(props, "dfs.datanode.address")
        host, port = parse_hostport(dn_addr)
        data_dir = require(props, "dfs.datanode.data.dir")
        handlers = {
            "PING": "PONG datanode-1",
            "DATADIR": "datadir=%s" % data_dir,
        }
        srv = bind(host, port, "datanode")
        with open(os.path.join(RUN_DIR, "datanode.ready"), "w") as fh:
            fh.write(str(os.getpid()))
        while True:
            try:
                srv.settimeout(0.5)
                conn, _ = srv.accept()
            except socket.timeout:
                continue
            srv.settimeout(None)
            handle(conn, handlers)


if __name__ == "__main__":
    main()
