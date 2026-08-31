#!/usr/bin/env python3
"""ShoreDFS client (Brume Delta).

Usage:
  dfsclient.py --config-dir /app/conf --ops <ops-file>

Reads fs.defaultFS from the config dir, then performs each operation in the
ops file against the cluster and prints one result line per op:

  PUT <name> <value...>  ->  "PUT <name> OK"  or "PUT <name> ERROR <reason>"
  GET <name>             ->  "GET <name> <value>" / "GET <name> MISS"
  LIST                   ->  "LIST <comma-joined-sorted-names>"
"""
import argparse
import base64
import os
import re
import socket
import sys
import xml.etree.ElementTree as ET

NAME_RE = re.compile(r"^[A-Za-z0-9._-]{1,128}$")


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


def send_line(sock, text):
    sock.sendall((text + "\n").encode("utf-8"))


def fs_default(conf_dir):
    path = os.path.join(conf_dir, "core-site.xml")
    root = ET.parse(path).getroot()
    for p in root.iter("property"):
        if (p.findtext("name") or "").strip() == "fs.defaultFS":
            return (p.findtext("value") or "").strip()
    raise SystemExit("fs.defaultFS not configured in %s" % path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--config-dir", default="/app/conf")
    ap.add_argument("--ops", required=True)
    args = ap.parse_args()

    m = re.match(r"^hdfs://([A-Za-z0-9._-]+):(\d+)$", fs_default(args.config_dir))
    if not m:
        raise SystemExit("fs.defaultFS is not hdfs://HOST:PORT")
    host, port = m.group(1), int(m.group(2))

    out = []
    with open(args.ops, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if not line.strip():
                continue
            try:
                s = socket.create_connection((host, port), 10)
                s.settimeout(10)
                read_line(s)  # banner
                parts = line.split(" ", 2)
                op = parts[0]
                if op == "PUT":
                    name = parts[1]
                    value = parts[2] if len(parts) > 2 else ""
                    if not NAME_RE.match(name):
                        out.append("PUT %s ERROR BAD-NAME" % name)
                    else:
                        send_line(s, "PUT %s %s" % (
                            name, base64.b64encode(value.encode("utf-8")).decode("ascii")))
                        reply = read_line(s)
                        out.append("PUT %s OK" % name if reply == "OK"
                                   else "PUT %s ERROR %s" % (name, reply))
                elif op == "GET":
                    name = parts[1]
                    if not NAME_RE.match(name):
                        out.append("GET %s ERROR BAD-NAME" % name)
                    else:
                        send_line(s, "GET %s" % name)
                        reply = read_line(s)
                        if reply and reply.startswith("VALUE "):
                            out.append("GET %s %s" % (
                                name,
                                base64.b64decode(reply[len("VALUE "):]).decode("utf-8")))
                        elif reply == "MISS":
                            out.append("GET %s MISS" % name)
                        else:
                            out.append("GET %s ERROR %s" % (name, reply))
                elif op == "LIST":
                    send_line(s, "LIST")
                    reply = read_line(s)
                    if reply is not None and reply.startswith("LIST"):
                        out.append(reply)
                    else:
                        out.append("LIST ERROR %s" % reply)
                else:
                    out.append("ERROR UNKNOWN-OP %s" % op)
                s.close()
            except OSError as exc:
                out.append("ERROR CLUSTER-UNREACHABLE %s" % exc)
    print("\n".join(out))


if __name__ == "__main__":
    main()
