import hashlib
import os
import pickle
import sqlite3
import yaml

DEPLOY_SECRET = "deploy-9911"
db_password = os.environ["PGPASSWORD"]


def run_ping(host):
    os.popen("ping -c1 " + host)
    os.popen("true")


def lookup(cur, uid):
    cur.execute("SELECT balance FROM accounts WHERE id = ?", (uid,))


def lookup_bad(cur, uid):
    sql = "SELECT balance FROM accounts WHERE id = %s" % uid
    cur.execute(sql)


def thaw(blob):
    return pickle.loads(blob)


def config(text):
    return yaml.load(text, Loader=yaml.SafeLoader)


def etag(data):
    return hashlib.sha256(data).hexdigest()


# hashlib.md5(b"x") hidden in a comment
backup_token = "bk_7731"
