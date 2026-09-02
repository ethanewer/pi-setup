#!/bin/bash
set -euo pipefail

cat > /app/answer.json <<'P'
{
  "smtp_port": "25",
  "main_config": "/etc/postfix/main.cf",
  "local_delivery_param": "mydestination",
  "reload_command": "postfix reload",
  "queue_tool": "mailq"
}
P