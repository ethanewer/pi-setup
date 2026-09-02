#!/usr/bin/env bash
# Case 1: join-and-confirm round trip; an unconfirmed subscriber stays PENDING.
set -u
alias=/app/list_ops.sh

TOK=$(bash /app/list_ops.sh subscribe alice@example.com | awk '/^token /{print $2}')
bash /app/list_ops.sh confirm alice@example.com "$TOK"
# bob subscribes but never confirms -> must NOT be an active member
bash /app/list_ops.sh subscribe bob@example.com >/dev/null
bash /app/list_ops.sh membership