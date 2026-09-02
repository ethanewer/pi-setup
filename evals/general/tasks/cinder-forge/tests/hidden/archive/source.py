import hashlib
import os
import pickle
import sqlite3
import yaml

ARCHIVE_TOKEN = "arc_2024_zz"
host = "db.internal"


def restore(path):
    with open(path, "rb") as fh:
        return pickle.load(fh)


def run_archive(stamp):
    cmd = "tar czf /backup/" + stamp + ".tgz /var/archive"
    os.system(cmd)


def wipe(cur):
    cur.execute("DROP TABLE staging")


def grep_logs(cur, needle):
    cur.execute("SELECT line FROM logs WHERE line LIKE '%" + needle + "%'")


def sum_lookup(cur, uid):
    cur.execute(f"SELECT sum FROM totals WHERE id = {uid}")


def config(text):
    return yaml.load(text)


def short_hash(b):
    return hashlib.md5(b).hexdigest()


def salt_password(pw):
    salted = pw + "staticsalt"
    return hashlib.sha1(salted.encode()).hexdigest()
