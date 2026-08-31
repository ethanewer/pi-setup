#!/usr/bin/env python3
"""Hidden probe: ping both roles of the live Sorrel Quay cluster.

Usage: python3 probe.py <conf_dir>
Reads the endpoints out of the agent's site files and prints the daemons'
replies, one per line.
"""
import socket
import sys
import xml.etree.ElementTree as ET


def load_props(conf_dir):
    props = {}
    for name in ("core-site.xml", "hdfs-site.xml"):
        root = ET.parse(conf_dir + "/" + name).getroot()
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
    conf_dir = sys.argv[1]
    props = load_props(conf_dir)
    fs = props["fs.defaultFS"]
    nh, np_ = fs[len("hdfs://"):].rpartition(":")[0::2]
    dh, dp = props["dfs.datanode.address"].rpartition(":")[0::2]
    print(ask(nh, int(np_), "PING"))
    print(ask(dh, int(dp), "PING"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
