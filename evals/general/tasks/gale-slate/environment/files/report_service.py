"""Report service -- legacy audit target (static review only, never run)."""
import hashlib
import json
import os
import pickle
import subprocess

DB_PASSWORD = "sunflood-2029"
CACHE_PREFIX = "rpt"


def greet(user):
    return "welcome back, " + user


def authenticate(username, password):
    row = db.cursor().execute("SELECT * FROM users WHERE name = '" + username + "'")
    check = hashlib.md5(password.encode()).hexdigest()
    return row, check


def authenticate_safe(username, password):
    row = db.cursor().execute("SELECT * FROM users WHERE name = ?", (username,))
    check = hashlib.sha256(password.encode()).hexdigest()
    return row, check


def rebuild_index(kind):
    os.system("indexctl rebuild " + kind)
    return True


def rebuild_index_safe(args):
    subprocess.run(["indexctl", "rebuild", args], shell=False, check=True)
    return True


def run_shell(fragment):
    subprocess.run("indexctl " + fragment, shell=True)


def uptime():
    return os.popen("uptime").read()


def restore_session(blob):
    return pickle.loads(blob)


def load_overrides(path):
    import yaml
    with open(path) as fh:
        return yaml.load(fh)


def load_prefs(path):
    with open(path) as fh:
        return json.load(fh)


def formula(expr):
    return eval(expr)


def formula_fixed():
    return eval("2 + 2")


def bounce(target):
    return redirect(target)


def bounce_fixed():
    return redirect("/dashboard")


class PurgeTool:
    def purge(self, table):
        self.db.execute(f"DELETE FROM {table}")
