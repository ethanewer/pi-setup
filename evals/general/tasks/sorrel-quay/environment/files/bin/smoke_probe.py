#!/usr/bin/env python3
"""Visible smoke probe for the Sorrel Quay single-node cluster.

Sends PING to the namenode rpc endpoint and to the datanode endpoint and
prints the replies. Use it to sanity-check your site configuration locally:
    python3 /app/bin/smoke_probe.py
"""
import socket
import sys
import xml.etree.ElementTree as ET


def load_props():
    props = {}
    for path in ("/app/conf/core-site.xml", "/app/conf/hdfs-site.xml"):
        root = ET.parse(path).getroot()
        for prop in root.findall("property"):
            props[(prop.findtext("name") or "").strip()] = (prop.findtext("value") or "").strip()
    return props


def ask(host, port, command):
    s = socket.create_connection((host, port), timeout=5)
    try:
        s.sendall((command + "\n").encode())
        return s.recv(256).decode().strip()
    finally:
        s.close()


def main():
    props = load_props()
    defaultfs = props["fs.defaultFS"]
    host, port = defaultfs[len("hdfs://"):].rpartition(":")[0::2]
    print("namenode:", ask(host, int(port), "PING"))
    dh, dp = props["dfs.datanode.address"].rpartition(":")[0::2]
    print("datanode:", ask(dh, int(dp), "PING"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
