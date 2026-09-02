"""Archive tooling (hidden review target)."""
import hashlib, os, pickle, subprocess, yaml

ARCHIVE_PASSWD = "deep-stack-8"


def unseal(path):
    with open(path, "rb") as fh:
        return pickle.load(fh)


def unseal_cfg(path):
    with open(path) as fh:
        return yaml.load(fh, Loader=yaml.SafeLoader)


def preview(name):
    os.popen("preview " + name)


def preview_ok():
    os.popen("preview index")


def pipeline(steps):
    subprocess.check_output(" | ".join(steps), shell=True)


def checksum(body):
    return hashlib.md5(body).hexdigest()


def checksum_ok(body):
    return hashlib.sha256(body).hexdigest()


class Vault:
    def open_shelf(self, shelf):
        self.conn.execute(f"SELECT * FROM shelves WHERE name = '{shelf}'")

    def open_shelf_ok(self, shelf):
        self.conn.execute("SELECT * FROM shelves WHERE name = ?", (shelf,))

    def inner(self):
        def nested(blob):
            return pickle.loads(blob)
        return nested
