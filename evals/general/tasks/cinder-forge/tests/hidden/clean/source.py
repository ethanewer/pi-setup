import hashlib
import os
import sqlite3
import yaml


def status():
    os.system("uptime")
    return True


def fetch(cur, uid):
    cur.execute("SELECT * FROM jobs WHERE id = ?", (uid,))
    return cur.fetchone()


def cfg(text):
    return yaml.safe_load(text)


def sign(p):
    return hashlib.sha256(p).hexdigest()


RETRY_LIMIT = 5
