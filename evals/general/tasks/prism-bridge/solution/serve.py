#!/usr/bin/env python3
"""prism-bridge : distributed file-hashing service worker.

Modes:
  python3 /app/serve.py <input_dir> <manifest_path>
      Hash every top-level regular file in <input_dir> with
      PBKDF2-HMAC-SHA256 (salt = sha256(basename), 60000 iterations) using a
      ProcessPoolExecutor (real worker *processes*, not threads), write one
      '<basename>\\t<hexdigest>' line per file (sorted by basename) to
      <manifest_path>, and (re)create exactly three worker marker files in
      /app/markers: STARTED.marker, WORKERS.marker, COMPLETED.marker.

  python3 /app/serve.py --status
      Print the installed java and hadoop versions as two lines:
          java  <major.minor...>
          hadoop <release>
"""
import hashlib
import os
import shutil
import subprocess
import sys
import time

WORKERS = 4
ITERATIONS = 60000
MARKER_DIR = "/app/markers"


def pbkdf2_hex(path):
    with open(path, "rb") as fh:
        data = fh.read()
    salt = hashlib.sha256(os.path.basename(path).encode()).digest()
    return hashlib.pbkdf2_hmac("sha256", data, salt, ITERATIONS).hex()


def hash_job(path):
    return os.path.basename(path), pbkdf2_hex(path), os.getpid()


def write_manifest(items, manifest_path):
    lines = sorted((name + "\t" + hexd for name, hexd, _ in items))
    with open(manifest_path, "w") as fh:
        fh.write("\n".join(lines) + "\n")


def write_markers(filenames, items, started):
    os.makedirs(MARKER_DIR, exist_ok=True)
    with open(os.path.join(MARKER_DIR, "STARTED.marker"), "w") as fh:
        fh.write("started %d\nfiles %d\n" % (started, len(filenames)))
    pids = sorted(set(pid for _, _, pid in items))
    with open(os.path.join(MARKER_DIR, "WORKERS.marker"), "w") as fh:
        for pid in pids:
            fh.write("worker %d\n" % pid)
    with open(os.path.join(MARKER_DIR, "COMPLETED.marker"), "w") as fh:
        fh.write("completed %d\nfiles %d\nhashes %d\n"
                 % (int(time.time()), len(filenames), len(items)))


### ---- status mode (java + hadoop versions) ----
def detect_java():
    j = shutil.which("java")
    if not j:
        return None, None
    real = os.path.realpath(j)
    java_home = os.path.dirname(os.path.dirname(real))
    out = subprocess.run(["java", "-version"], capture_output=True, text=True)
    version_line = (out.stderr or out.stdout).splitlines()[:1]
    return (java_home, version_line[0] if version_line else None)


def detect_hadoop(java_home):
    hbin = "/opt/hadoop/bin/hadoop"
    if not os.path.exists(hbin):
        return None
    env = dict(os.environ)
    if java_home:
        env["JAVA_HOME"] = java_home
    out = subprocess.run([hbin, "version"], capture_output=True, text=True, env=env)
    first = out.stdout.splitlines()[:1]
    return first[0] if first else None


def status_main():
    java_home, java_raw = detect_java()
    hadoop_raw = detect_hadoop(java_home)
    if not java_raw or not java_home:
        print("java <missing>")
    else:
        print("java " + _short(java_raw))
    if not hadoop_raw:
        print("hadoop <missing>")
    else:
        print("hadoop " + _short(hadoop_raw))
    if not java_raw or not hadoop_raw:
        sys.exit(1)
    return 0


def _short(s):
    # 'openjdk version "11.0.32" 2026-...' or 'Hadoop 3.3.6' -> clean token
    import re
    m = re.search(r'(\d+\.\d+(?:\.\d+)?)', s)
    return m.group(1) if m else s.strip()


def hashing_main(input_dir, manifest_path):
    files = sorted(
        f for f in os.listdir(input_dir)
        if os.path.isfile(os.path.join(input_dir, f))
    )
    paths = [os.path.join(input_dir, f) for f in files]
    started = int(time.time())
    if not paths:
        write_manifest([], manifest_path)
        write_markers(files, [], started)
        return 0
    import concurrent.futures
    with concurrent.futures.ProcessPoolExecutor(max_workers=WORKERS) as ex:
        items = list(ex.map(hash_job, paths))
    write_manifest(items, manifest_path)
    write_markers(files, items, started)
    return 0


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--status":
        return status_main()
    if len(sys.argv) == 3:
        return hashing_main(sys.argv[1], sys.argv[2])
    print("usage: %s <input_dir> <manifest_path>   |   %s --status" %
          (sys.argv[0], sys.argv[0]), file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())
