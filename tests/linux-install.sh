#!/usr/bin/env bash
# Install this setup on a clean Linux machine, the way a new machine would do it.
#
#   tests/linux-install.sh [image] [ref]
#
# Defaults to ubuntu:24.04 and the main branch. Needs Docker. Takes a few minutes,
# nearly all of it Bun and Pi downloading.
#
# This exists because portability bugs in install.sh, install.ps1, lib/install.mjs and
# bin/pi-setup-doctor — GNU vs BSD stat, /usr/bin/git being a stub on macOS but real on
# Linux, a missing unzip, no node anywhere — are invisible from a Mac by construction.
# One of them shipped: a check that produced a false PROBLEM on every Linux install,
# fixed without anyone ever seeing a Linux install.
#
# It tests the published install.sh over the network rather than the working tree, so
# commit and push before running it. That is deliberate: the piped one-liner in the
# README is the thing a new machine actually executes.
set -uo pipefail
IMAGE="${1:-ubuntu:24.04}"
REF="${2:-main}"

command -v docker >/dev/null 2>&1 || { echo "tests/linux-install.sh: docker is required" >&2; exit 2; }

docker run --rm -i -e REF="$REF" "$IMAGE" bash -s <<'IN'
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null 2>&1
apt-get install -y -qq curl git ca-certificates openssl >/dev/null 2>&1

# Some corporate networks terminate TLS with their own CA, which a fresh container does
# not trust. That is a property of the network, not of the installer, so if the plain
# fetch fails, trust whatever is actually presenting itself and carry on.
if ! curl -fsSI https://raw.githubusercontent.com >/dev/null 2>&1; then
  echo "network: TLS interception detected, trusting the intercepting CA"
  for host in raw.githubusercontent.com registry.npmjs.org bun.sh github.com objects.githubusercontent.com; do
    openssl s_client -showcerts -connect "$host:443" -servername "$host" </dev/null 2>/dev/null \
      | awk '/BEGIN CERT/,/END CERT/'
  done > /usr/local/share/ca-certificates/intercept.crt
  update-ca-certificates >/dev/null 2>&1
  curl -fsSI https://raw.githubusercontent.com >/dev/null 2>&1 \
    || { echo "network: still failing, aborting"; exit 1; }
fi
echo "network: TLS ok"

URL="https://raw.githubusercontent.com/ethanewer/pi-setup/$REF/install.sh"
useradd -m tester

echo
echo "=== [1] no unzip installed: the installer must refuse at the door"
# Bun's own installer needs unzip. Without this precondition the install dies partway
# through with Bun's error, after having already written half a setup.
su - tester -c "curl -fsSL '$URL' | PI_SETUP_REF='$REF' PI_SETUP_SKIP_BROWSER_INSTALL=1 bash" 2>&1 | tail -2

echo
echo "=== [2] install unzip, then the real thing"
apt-get install -y -qq unzip >/dev/null 2>&1
su - tester -c "curl -fsSL '$URL' | PI_SETUP_REF='$REF' PI_SETUP_SKIP_BROWSER_INSTALL=1 bash" >/tmp/out.log 2>&1
INSTALL_EXIT=$?
echo "install exit=$INSTALL_EXIT"
[[ "$INSTALL_EXIT" == "0" ]] || { echo "--- install log ---"; cat /tmp/out.log; }
tail -4 /tmp/out.log

echo
echo "=== [3] versions"
su - tester -c 'export PATH=$HOME/.local/bin:$PATH; pi --version; p --version; piwf --version; agent-browser --version'

echo
echo "=== [4] doctor, on a machine with no node at all"
# The doctor and install.sh both shell out to a JS runtime. Linux users installing this
# will often have Bun and nothing else, so nothing may assume node exists.
su - tester -c 'command -v node >/dev/null && echo "node present (not the case being tested)" || echo "(no node installed)"'
su - tester -c 'export PATH=$HOME/.local/bin:$HOME/.bun/bin:$PATH; bash ~/.pi/agent/setup-src/bin/pi-setup-doctor --offline'
echo "doctor exit=$?"

echo
echo "=== [5] doctor, with node also installed"
# The doctor's JS fallback chain prefers node when it is on PATH, and the Pi AI
# reasoning verifier is an ESM script with a bun shebang that node cannot load as .js.
# A machine with both runtimes must still pass the behavior check; running the
# verifier under node shipped as a false PROBLEM on every such Linux box.
apt-get install -y -qq nodejs >/dev/null 2>&1
su - tester -c 'command -v node && node --version'
su - tester -c 'export PATH=$HOME/.local/bin:$HOME/.bun/bin:$PATH; bash ~/.pi/agent/setup-src/bin/pi-setup-doctor --offline'
echo "doctor exit=$?"
IN
