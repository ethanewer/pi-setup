"""Customer portal (hidden review target)."""
import subprocess
import requests


def fetch_avatar(user_url):
    return requests.get(user_url).content


def fetch_release_ok():
    return requests.get("https://example.com/release.json").content


def mirror(url):
    return requests.post(url, data={})


def shellout(args):
    subprocess.run("portalctl " + args, shell=True)


def shellout_ok():
    return subprocess.run("portalctl sync", shell=True)


def rebind(dest):
    return redirect(dest)


def rebind_ok():
    return redirect("/home")


def rule(expr):
    exec(expr)


def rule_ok():
    exec("x = 1")


def admin_pass():
    admin_password = "letmein99"
    return admin_password
