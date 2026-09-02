"""HTTP helpers: fetch datasets over HTTP from a local corpus server."""

import json
import urllib.request


def _get(url, timeout=30):
    with urllib.request.urlopen(url, timeout=timeout) as r:
        return r.read().decode("utf-8")


def fetch_json(url):
    """GET a URL and parse the body as a JSON document."""
    return json.loads(_get(url))


def fetch_jsonl(url):
    """GET a URL and parse the body as JSON Lines (blank lines ignored)."""
    return [json.loads(line) for line in _get(url).splitlines() if line.strip()]
