#!/usr/bin/env python3
"""Juniper Notch relay tool (agent deliverable).

Modes:
  python3 /app/q.py                 -> publish /app/job.json (retain) then survey.
  python3 /app/q.py publish <file>  -> publish the directive in <file> (retain).
  python3 /app/q.py survey          -> re-run only the survey, overwrite
                                       /app/roundtrip.out.

Discovery: endpoints come from /app/relay/station.toml (bus host/port/topic and
gate port). The bus is MQTT and unauthenticated; directives are published with
retain=true to the inbox topic so a worker that subscribes later still receives
them. The survey is a raw TCP text protocol: connect, send "MAP", pick the site
nearest the target by Manhattan distance (ties -> lexicographically smallest),
send "SURVE <site>", and record the site reply line.
"""
import json
import os
import socket
import sys
import time
import tomllib

from paho.mqtt import client as mqtt

APP = "/app"
RELAY = os.path.join(APP, "relay")
STATION = os.path.join(RELAY, "station.toml")
JOB = os.path.join(APP, "job.json")
OUT = os.path.join(APP, "roundtrip.out")


def load_station():
    with open(STATION, "rb") as fh:
        cfg = tomllib.load(fh)
    b = cfg["bus"]
    g = cfg["gate"]
    return {
        "broker_host": str(b["host"]),
        "broker_port": int(b["port"]),
        "topic": str(b["inbox_topic"]),
        "gate_host": str(g["host"]),
        "gate_port": int(g["port"]),
    }


def publish_directive(cfg, directive):
    c = mqtt.Client(client_id="juniper-agent-%d" % os.getpid())
    c.connect(cfg["broker_host"], cfg["broker_port"], keepalive=30)
    c.loop_start()
    try:
        info = c.publish(cfg["topic"], json.dumps(directive), qos=1, retain=True)
        info.wait_for_publish(timeout=5)
        time.sleep(0.5)
    finally:
        c.loop_stop()
    return True


def read_json_line(sock):
    buf = b""
    while not buf.endswith(b"\n"):
        chunk = sock.recv(1)
        if not chunk:
            break
        buf += chunk
    return json.loads(buf.decode("utf-8"))


def survey(cfg):
    s = socket.create_connection((cfg["gate_host"], cfg["gate_port"]), timeout=8)
    s.settimeout(8)
    try:
        s.sendall(b"MAP\n")
        mp = read_json_line(s)
        target = mp["target"]

        def manhattan(site):
            return abs(site["row"] - target["row"]) + abs(site["col"] - target["col"])

        nearest = min(mp["sites"], key=lambda site: (manhattan(site), site["name"]))
        s.sendall(("SURVE %s\n" % nearest["name"]).encode("utf-8"))
        reply = read_json_line(s)
        if not reply.get("ok"):
            raise RuntimeError("survey failed: %r" % (reply,))
        with open(OUT, "w") as fh:
            fh.write(json.dumps(reply) + "\n")
        return reply
    finally:
        s.close()


def main():
    cfg = load_station()
    args = sys.argv[1:]
    if args and args[0] == "publish" and len(args) >= 2:
        with open(args[1]) as fh:
            directive = json.load(fh)
        publish_directive(cfg, directive)
        return
    if args and args[0] == "survey":
        survey(cfg)
        return
    # Default: publish /app/job.json then survey the active map.
    with open(JOB) as fh:
        directive = json.load(fh)
    publish_directive(cfg, directive)
    survey(cfg)


if __name__ == "__main__":
    main()