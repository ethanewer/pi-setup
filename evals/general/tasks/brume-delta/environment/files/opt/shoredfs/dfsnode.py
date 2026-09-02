#!/usr/bin/env python3
"""ShoreDFS single-node emulator: namenode + datanode roles (Brume Delta).

Usage: dfsnode.py <namenode|datanode>

Both roles merge /app/conf/core-site.xml and /app/conf/hdfs-site.xml into one
property map, validate their configuration, bind their sockets, and exchange
ready markers under /app/run:

  namenode  : binds fs.defaultFS host:port, validates that
              dfs.namenode.rpc-address names the same host:port, creates
              dfs.namenode.name.dir, writes /app/run/namenode.ready, serves
              REGISTER/PUT/GET/LIST with a SHOREDFS-NN READY banner.
  datanode  : binds dfs.datanode.address, validates dfs.replication, creates
              dfs.datanode.data.dir, registers with the namenode at the
              fs.defaultFS address, writes /app/run/datanode.ready, serves
              BLOCK/READ with a SHOREDFS-DN READY banner.
"""
import base64
import os
import re
import socket
import sys
import threading
import time
import xml.etree.ElementTree as ET

CONF_DIR = os.environ.get("SHOREDFS_CONF", "/app/conf")
RUN_DIR = "/app/run"

FS_RE = re.compile(r"^hdfs://([A-Za-z0-9._-]+):(\d+)$")
ADDR_RE = re.compile(r"^([A-Za-z0-9._-]+):(\d+)$")
NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


def die(msg):
    sys.stderr.write("shoredfs: %s\n" % msg)
    sys.exit(2)


def load_props():
    props = {}
    for fname in ("core-site.xml", "hdfs-site.xml"):
        path = os.path.join(CONF_DIR, fname)
        if not os.path.isfile(path):
            die("missing config file %s" % path)
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as exc:
            die("invalid XML in %s: %s" % (path, exc))
        for p in root.iter("property"):
            name = p.findtext("name")
            val = p.findtext("value")
            if not name:
                continue
            props[name.strip()] = (val or "").strip()
    return props


def send_line(sock, text):
    sock.sendall((text + "\n").encode("utf-8"))


def read_line(sock):
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = sock.recv(4096)
        if not chunk:
            return None
        buf += chunk
        if len(buf) > 1 << 20:
            return None
    return buf.decode("utf-8", "replace").rstrip("\n")


def connect_to(host, port, timeout=5):
    return socket.create_connection((host, port), timeout)


def write_marker(name, text):
    os.makedirs(RUN_DIR, exist_ok=True)
    with open(os.path.join(RUN_DIR, name), "w", encoding="utf-8") as fh:
        fh.write(text + "\n")


def serve_forever(srv, handler):
    while True:
        try:
            conn, _ = srv.accept()
        except OSError:
            break
        conn.settimeout(15)
        t = threading.Thread(target=handler, args=(conn,), daemon=True)
        t.start()


def run_namenode(props):
    fs = props.get("fs.defaultFS", "")
    m = FS_RE.match(fs)
    if not m:
        die("bad/empty fs.defaultFS %r; expected hdfs://HOST:PORT" % fs)
    host, port = m.group(1), int(m.group(2))
    rpc = props.get("dfs.namenode.rpc-address", "")
    if rpc != "%s:%d" % (host, port):
        die("dfs.namenode.rpc-address %r does not match fs.defaultFS %s:%d "
            "(complementary namenode config required)" % (rpc, host, port))
    namedir = props.get("dfs.namenode.name.dir", "")
    if not namedir:
        die("missing/empty dfs.namenode.name.dir")
    os.makedirs(namedir, exist_ok=True)

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(16)
    write_marker("namenode.ready", "ready addr=%s:%d" % (host, port))

    lock = threading.Lock()
    state = {"datanode": None, "names": set()}

    def talk_to_dn(cmd):
        with lock:
            dn = state["datanode"]
        if not dn:
            return "ERROR NO-DATANODE"
        md = ADDR_RE.match(dn)
        if not md:
            return "ERROR BAD-DN"
        try:
            s = connect_to(md.group(1), int(md.group(2)), timeout=5)
            read_line(s)  # banner
            send_line(s, cmd)
            reply = read_line(s)
            s.close()
            return reply or "ERROR DN-NO-REPLY"
        except OSError:
            return "ERROR DN-UNREACHABLE"

    def handle(conn):
        try:
            send_line(conn, "SHOREDFS-NN READY %s:%d" % (host, port))
            line = read_line(conn)
            if not line:
                return
            parts = line.split(" ", 2)
            op = parts[0]
            if op == "REGISTER" and len(parts) >= 2:
                with lock:
                    state["datanode"] = parts[1]
                send_line(conn, "REGISTERED")
            elif op == "PUT" and len(parts) == 3:
                name, b64 = parts[1], parts[2]
                if not NAME_RE.match(name):
                    send_line(conn, "ERROR BAD-NAME")
                    return
                reply = talk_to_dn("BLOCK %s %s" % (name, b64))
                if reply == "SAVED":
                    with lock:
                        state["names"].add(name)
                    send_line(conn, "OK")
                else:
                    send_line(conn, "ERROR %s" % reply)
            elif op == "GET" and len(parts) == 2:
                if not NAME_RE.match(parts[1]):
                    send_line(conn, "ERROR BAD-NAME")
                    return
                reply = talk_to_dn("READ %s" % parts[1])
                if reply and reply.startswith("DATA "):
                    send_line(conn, "VALUE %s" % reply[len("DATA "):])
                elif reply == "MISS":
                    send_line(conn, "MISS")
                else:
                    send_line(conn, "ERROR %s" % (reply or "DN-NO-REPLY"))
            elif op == "LIST":
                with lock:
                    names = sorted(state["names"])
                send_line(conn, "LIST %s" % ",".join(names))
            else:
                send_line(conn, "ERROR BAD-COMMAND")
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    serve_forever(srv, handle)


def run_datanode(props):
    dn = props.get("dfs.datanode.address", "")
    md = ADDR_RE.match(dn)
    if not md:
        die("bad/empty dfs.datanode.address %r; expected HOST:PORT" % dn)
    host, port = md.group(1), int(md.group(2))
    repl = props.get("dfs.replication", "")
    if not repl.isdigit() or int(repl) < 1:
        die("dfs.replication must be a positive integer, got %r" % repl)
    datadir = props.get("dfs.datanode.data.dir", "")
    if not datadir:
        die("missing/empty dfs.datanode.data.dir")
    os.makedirs(datadir, exist_ok=True)
    fs = props.get("fs.defaultFS", "")
    mfs = FS_RE.match(fs)
    if not mfs:
        die("bad/empty fs.defaultFS %r" % fs)
    nn_host, nn_port = mfs.group(1), int(mfs.group(2))

    def block_path(name):
        return os.path.join(datadir, name + ".b64")

    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(16)

    def handle(conn):
        try:
            send_line(conn, "SHOREDFS-DN READY %s:%d" % (host, port))
            line = read_line(conn)
            if not line:
                return
            parts = line.split(" ", 2)
            op = parts[0]
            if op == "BLOCK" and len(parts) == 3:
                name, b64 = parts[1], parts[2]
                if not NAME_RE.match(name):
                    send_line(conn, "ERROR BAD-NAME")
                    return
                try:
                    base64.b64decode(b64, validate=True)
                except Exception:
                    send_line(conn, "ERROR BAD-PAYLOAD")
                    return
                with open(block_path(name), "w", encoding="utf-8") as fh:
                    fh.write(b64)
                send_line(conn, "SAVED")
            elif op == "READ" and len(parts) == 2:
                if not NAME_RE.match(parts[1]):
                    send_line(conn, "ERROR BAD-NAME")
                    return
                if os.path.isfile(block_path(parts[1])):
                    with open(block_path(parts[1]), encoding="utf-8") as fh:
                        send_line(conn, "DATA %s" % fh.read().strip())
                else:
                    send_line(conn, "MISS")
            else:
                send_line(conn, "ERROR BAD-COMMAND")
        except OSError:
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    t = threading.Thread(target=serve_forever, args=(srv, handle), daemon=True)
    t.start()

    # Register with the namenode (retry up to 30 s while it starts).
    registered = False
    deadline = time.time() + 30
    while time.time() < deadline and not registered:
        try:
            s = connect_to(nn_host, nn_port, timeout=5)
            read_line(s)  # namenode banner
            send_line(s, "REGISTER %s:%d" % (host, port))
            reply = read_line(s)
            s.close()
            if reply == "REGISTERED":
                registered = True
        except OSError:
            time.sleep(0.5)
    if not registered:
        die("could not register with namenode at %s:%d" % (nn_host, nn_port))

    write_marker("datanode.ready",
                 "registered namenode=%s:%d self=%s:%d" % (nn_host, nn_port, host, port))
    t.join()


def main():
    if len(sys.argv) != 2 or sys.argv[1] not in ("namenode", "datanode"):
        sys.stderr.write("usage: dfsnode.py <namenode|datanode>\n")
        sys.exit(2)
    props = load_props()
    if sys.argv[1] == "namenode":
        run_namenode(props)
    else:
        run_datanode(props)


if __name__ == "__main__":
    main()
