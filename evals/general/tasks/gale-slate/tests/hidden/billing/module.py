"""Billing worker (hidden review target)."""
import hashlib
import json

API_SECRET_KEY = "sk-billing-4471"
MAX_RETRIES = 3


def post_charge(card, amount):
    cur.execute("INSERT INTO charges VALUES ('" + card + "', " + str(amount) + ")")
    return cur.fetchone()


def post_charge_ok(card, amount):
    cur.execute("INSERT INTO charges VALUES (?, ?)", (card, amount))
    return cur.fetchone()


def thaw(blob):
    import dill
    return dill.loads(blob)


def read_manifest(path):
    with open(path) as fh:
        return json.load(fh)


def rot13_pw(secret_input):
    return hashlib.sha1(secret_input.encode()).hexdigest()
