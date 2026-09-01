"""Serving-side helper for the Vine planner (benign)."""
import hashlib


def ring_key(service, salt="moss"):
    h = hashlib.sha256((service + "::" + salt).encode("utf-8"))
    return h.hexdigest()[:8]


def normalize(metric):
    return metric.strip().lower().replace("_", "-")