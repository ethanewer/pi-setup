"""Wire protocol: JSON-lines events in, enriched JSON-lines events out.

Input events arrive one JSON object per line.  Clients reach the service from
many collectors, so the ``client`` field may carry arbitrary casing, padding,
and an optional collector tag suffix (for example ``"Acct 001~b7"``); the
canonical spelling is defined in :func:`normalise_client`.  The service emits
exactly one enriched object per input event, in input order, containing every
original field plus the enrichment fields produced by the engine.
"""
import json
import re
import time
from dataclasses import dataclass

REQUIRED_FIELDS = ("client", "ts", "kind")

# Enrichment fields the engine attaches to every output event.
ENRICHED_FIELDS = (
    "client_key",
    "day",
    "segment",
    "digest_mean",
    "digest_energy",
    "digest_l1",
)

_TAG_RE = re.compile(r"~[0-9a-z]+")


class ProtocolError(ValueError):
    """Raised when an input line is not a well-formed event."""


def normalise_client(raw):
    """Canonical spelling of a client identifier.

    Client identifiers arrive from many collectors that case differently,
    pad or repeat whitespace, and append a collector tag ("Acct 001~b7", the
    batch watermark of the hop that forwarded the event).  None of that is
    part of the client's identity.  The canonical spelling - lowercase, runs
    of whitespace collapsed to a single space, collector tags stripped - is
    the one carried in the emitted ``client_key`` field and the one used
    wherever the service groups or keys by identity.
    """
    s = " ".join(_TAG_RE.sub("", raw.lower()).split())
    return s


def day_of(ts):
    """UTC calendar date for an epoch timestamp, ISO-8601 (YYYY-MM-DD)."""
    return time.strftime("%Y-%m-%d", time.gmtime(ts))


@dataclass
class Event:
    client: str
    ts: int
    kind: str
    amount: float
    orig: dict

    @classmethod
    def parse(cls, raw):
        """Parse one JSON-lines event from its raw text."""
        obj = json.loads(raw)  # JSONDecodeError -> ValueError
        if not isinstance(obj, dict):
            raise ProtocolError("event is not a JSON object")
        for k in REQUIRED_FIELDS:
            if k not in obj:
                raise ProtocolError("missing required field %r" % k)
        client = obj["client"]
        if not isinstance(client, str) or not client.strip():
            raise ProtocolError("client must be a non-blank string")
        ts = obj["ts"]
        if not isinstance(ts, int):
            raise ProtocolError("ts must be an integer")
        kind = obj["kind"]
        if not isinstance(kind, str):
            raise ProtocolError("kind must be a string")
        amount = obj.get("amount", 0.0)
        if not isinstance(amount, (int, float)):
            raise ProtocolError("amount must be numeric")
        return cls(client=client, ts=ts, kind=kind,
                   amount=float(amount), orig=obj)
