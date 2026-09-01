#!/usr/bin/env python3
"""Juniper Notch relay worker.

Subscribes to the inbox topic on the relay's MQ bus and applies "rebalance"
task directives. A directive is a retained JSON message:

    {
      "job_id":  "<alnum/_- string, 1..64>",
      "kind":    "rebalance",                 # must be exactly this
      "sector":  "north"|"south"|"east"|"west",
      "payload": [ 0..1e5 non-negative ints, length 1..12 ]
    }

When a directive validates, the worker writes a receipt under
/app/relay/applied/<job_id>.result.json containing the applied values and a
deterministic digest of the directive. Malformed directives are logged and
ignored (they never crash the loop and never produce a receipt).

This relay deliberately exposes the bus with no authentication; all traffic
is over loopback. Do not modify this worker.
"""
import json
import hashlib
import logging
import os
import re
import uuid

import numpy as np

from paho.mqtt import client as mqtt

APP = "/app"
RELAY = os.path.join(APP, "relay")
APPLIED = os.path.join(RELAY, "applied")

JOB_ID_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
ALLOWED_SECTORS = {"north", "south", "east", "west"}
log = logging.getLogger("worker")


def load_station():
    with open(os.path.join(RELAY, "station.toml"), "rb") as fh:
        cfg = __import__("tomllib").load(fh)
    b = cfg["bus"]
    return str(b["host"]), int(b["port"]), str(b["inbox_topic"])


def validate(body):
    if not isinstance(body, dict):
        return None
    job_id = body.get("job_id")
    kind = body.get("kind")
    sector = body.get("sector")
    payload = body.get("payload")
    if not isinstance(job_id, str) or not JOB_ID_RE.match(job_id):
        return None
    if kind != "rebalance":
        return None
    if sector not in ALLOWED_SECTORS:
        return None
    if not isinstance(payload, list) or not (1 <= len(payload) <= 12):
        return None
    if not all(isinstance(v, int) and not isinstance(v, bool)
               and 0 <= v <= 100000 for v in payload):
        return None
    return {"job_id": job_id, "kind": kind, "sector": sector, "payload": payload}


def digest(job_id, sector, payload):
    s = "%s|%s|%s|%d" % (job_id, sector, ",".join(str(v) for v in payload),
                         len(payload))
    return hashlib.sha256(s.encode()).hexdigest()[:16]


def apply_job(d):
    os.makedirs(APPLIED, exist_ok=True)
    arr = np.asarray(d["payload"], dtype=np.int64)
    mass = int(arr.sum())
    rec = {
        "job_id": d["job_id"],
        "kind": "rebalance",
        "sector": d["sector"],
        "payload_len": len(d["payload"]),
        "mass": mass,
        "digest": digest(d["job_id"], d["sector"], d["payload"]),
    }
    path = os.path.join(APPLIED, d["job_id"] + ".result.json")
    with open(path, "w") as fh:
        fh.write(json.dumps(rec))
    log.info("applied %s digest=%s", d["job_id"], rec["digest"])
    return path


def on_connect(cl, _u, _f, _rc):
    cl.subscribe(INBOX_TOPIC, qos=1)

INBOX_TOPIC = "juniper/jobs"


def on_message(_cl, _u, msg):
    try:
        body = json.loads(msg.payload.decode("utf-8"))
    except Exception:
        return
    v = validate(body)
    if v is None:
        log.info("ignored invalid directive len=%d", len(msg.payload))
        return
    apply_job(v)


def build_client(host, port, topic):
    global INBOX_TOPIC
    INBOX_TOPIC = topic
    c = mqtt.Client(client_id="juniper-worker-" + uuid.uuid4().hex[:8])
    c.on_connect = on_connect
    c.on_message = on_message
    return c


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    host, port, topic = load_station()
    c = build_client(host, port, topic)
    c.connect(host, port, keepalive=30)
    log.info("worker up: %s:%d topic=%s", host, port, topic)
    c.loop_forever()