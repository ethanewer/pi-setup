#!/bin/bash
# Oracle: does the real work for every vine-mantle deliverable. Uses only
# literal /app paths and never reads /tests.
set -euo pipefail

# ----------------------------------------------------------------- (A) solver
cat > /app/solve.py <<'PY'
#!/usr/bin/env python3
"""Vine Mantle vault solver (red-team recovery).

For any encrypted "same-scheme" archive given as an argument: enumerate
candidate passphrases, reduce them with the documented SHA-1 structural-count
filter, probe the encrypted header with p7zip, decrypt + extract the member,
parse the recovered credentials and write the requested JSON. When run with the
default paths it also writes /app/result/creds.txt.

Usage:
    python3 solve.py [vault_path] [out_json]
        vault_path default /app/vault/box.7z
        out_json   default /app/answer.json
"""
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path

PREFIX = "morn"
VAULT_DEF = Path("/app/vault/box.7z")
OUT_DEF = Path("/app/answer.json")
CREDS_DEF = Path("/app/result/creds.txt")


def shortlist():
    """Candidates whose units digit equals the SHA-1 hex 'letter' count."""
    keep = []
    for n in range(100, 1000):
        pw = "{}-{}".format(PREFIX, n)
        digest = hashlib.sha1(pw.encode("utf-8")).hexdigest()
        letters = sum(1 for ch in digest if ch in "abcdef")
        if (n % 10) == letters:
            keep.append(pw)
    return keep


def opens(archive, pw):
    """True iff pw correctly decrypts the archive header (7z test exit 0)."""
    r = subprocess.run(["7z", "t", "-y", "-p" + pw, str(archive)],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                       check=False)
    return r.returncode == 0


def find_password(archive):
    """First shortlist passphrase (ascending) that opens the archive."""
    for pw in shortlist():
        if opens(archive, pw):
            return pw
    return None


def extract(member_dest, archive, password):
    subprocess.run(["7z", "x", "-y", "-o{}".format(member_dest), "-p" + password,
                    str(archive)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=True)


def read_creds(member_dest):
    member = member_dest / "member.txt"
    if not member.exists():
        files = [p for p in member_dest.rglob("*") if p.is_file()]
        if len(files) != 1:
            raise RuntimeError("expected a single member file")
        member = files[0]
    creds = {}
    for line in member.read_text("utf-8", errors="replace").splitlines():
        if "=" not in line:
            continue
        key, _, val = line.partition("=")
        key, val = key.strip(), val.strip()
        if key == "app-username":
            creds["username"] = val
        elif key == "app-password":
            creds["password"] = val
    if "username" not in creds or "password" not in creds:
        raise RuntimeError("member missing app-username/app-password keys")
    return creds


def main(argv):
    vault = Path(argv[0]) if argv else VAULT_DEF
    out = Path(argv[1]) if len(argv) > 1 else OUT_DEF
    password = find_password(vault)
    if password is None:
        raise SystemExit("no shortlist passphrase opened {}".format(vault))
    dest = Path(tempfile.mkdtemp(prefix="manta_vault_"))
    subprocess.run(["7z", "x", "-y", "-o{}".format(dest), "-p" + password,
                   str(vault)],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   check=True)
    creds = read_creds(dest)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(creds, indent=2) + "\n", "utf-8")
    if out == OUT_DEF:
        CREDS_DEF.parent.mkdir(parents=True, exist_ok=True)
        CREDS_DEF.write_text("username: {}\npassword: {}\n".format(
            creds["username"], creds["password"]), "utf-8")
    print(json.dumps(creds, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
chmod +x /app/solve.py

# Run the recovered-scheme vault pipeline (writes answer.json + creds.txt).
python3 /app/solve.py /app/vault/box.7z /app/answer.json

# ----------------------------------------------------------------- (B) sanitize
sed -i 's/TKN-8v3K-99xq/REDACTED/g' /app/sanitize-repo/config/app.env
sed -i 's/tkn-8v3k-99xq/REDACTED/g' /app/sanitize-repo/docs/mapping.md

# ------------------------------------------------------------------ (C) jar
mkdir -p /app/dist
cd /app/jarupload/src
cat > com/lattice/JaxUpload.java <<'JV'
package com.lattice;

/**
 * Name resolver for the Lattice jar-dock upload service.
 *
 * Sanitized so that only the base filename survives: '/' and '\' and their
 * percent-encodings (%2F / %2f / %5C / %5c) act as separators; empty, single-dot
 * and parent-dot ("..") components are dropped so no path can climb out of the
 * dock; if nothing usable remains the fallback name is returned. The result is
 * always a bare, path-free filename.
 */
public final class JaxUpload {

    public static final String FALLBACK = "upload.jar";

    private JaxUpload() {
    }

    public static String resolve(String raw) {
        if (raw == null) {
            return FALLBACK;
        }
        String s = raw.replace("%2F", "/")
                      .replace("%2f", "/")
                      .replace("%5C", "\\")
                      .replace("%5c", "\\");
        String last = "";
        for (String part : s.split("[/\\\\]")) {
            if (part.isEmpty() || part.equals(".") || part.equals("..")) {
                continue;
            }
            last = part;
        }
        return last.isEmpty() ? FALLBACK : last;
    }
}
JV
rm -rf /app/jarupload/build
mkdir -p /app/jarupload/build
javac -d /app/jarupload/build com/lattice/JaxUpload.java com/lattice/Probe.java
(cd /app/jarupload/build && jar cf /app/dist/manta.jar com)

# ----------------------------------------------------------------------- (D) tls
mkdir -p /app/tls
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout /app/tls/portico.test.key -out /app/tls/portico.test.crt \
    -subj "/CN=portico.test" >/dev/null 2>&1
chmod 600 /app/tls/portico.test.key

echo "vine-mantle oracle complete"