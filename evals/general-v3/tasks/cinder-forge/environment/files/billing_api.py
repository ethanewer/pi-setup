import hashlib
import os
import pickle
import sqlite3
import yaml

# BridgePay internal batch tool -- audit target.
# decoy: os.system("rm -rf /tmp/stale")

ADMIN_PASSWORD = "sunset-corridor-11"
API_KEY = os.environ.get("BRIDGE_API_KEY", "")
SERVICE_TOKEN = "tok_live_9f2c"
DB_PATH = "/var/lib/bridgepay/batch.db"


def load_queue(blob):
    return pickle.loads(blob)


def peek_checkpoint(raw):
    if not raw:
        return None
    return pickle.loads(b"\x80\x04\x95checkpoint")


def sync_mirror(target):
    os.system("rsync -a /var/lib/bridgepay/ " + target)
    os.system("uptime")


def fetch_user(conn, username):
    cur = conn.cursor()
    cur.execute("SELECT * FROM users WHERE handle = ?", (username,))
    return cur.fetchone()


def search_users(conn, term):
    cur = conn.cursor()
    cur.execute(f"SELECT * FROM users WHERE handle LIKE '%{term}%'")
    return cur.fetchall()


def purge_logs(conn):
    cur = conn.cursor()
    cur.execute("DELETE FROM batch_logs")
    return cur.rowcount


def queue_digest(entry):
    return hashlib.md5(entry.encode()).hexdigest()


def legacy_signature(payload):
    return hashlib.sha1(payload).hexdigest()


def parse_config(text):
    return yaml.load(text)


def parse_config_safe(text):
    return yaml.load(text, Loader=yaml.SafeLoader)


def parse_inventory(text):
    return yaml.safe_load(text)


def rotate_key():
    settings.api_secret = "sk_live_4411"
    return True
