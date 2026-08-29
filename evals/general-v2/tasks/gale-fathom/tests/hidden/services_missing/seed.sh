#!/bin/bash
# Edge: the web (nginx) and SSH (openssh-server) packages are PURGED and the nginx
# config/marker/pid are gone. Provisioner must reinstall them non-interactively and
# bring the web server back up alongside a usable sshd.
DEBIAN_FRONTEND=noninteractive
dpkg -r --purge nginx nginx-common openssh-server openssh-sftp-server >/tmp/purge.log 2>&1 || true
rm -rf /var/www/fathom /app/nginx-fathom.conf /app/nginx.pid /app/nginx-error.log
