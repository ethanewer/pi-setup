#!/usr/bin/env bash
# Case 4: several addresses in one session; membership is sorted; a
# subscribed-but-unconfirmed address is excluded.
set -u

TOK1=$(bash /app/list_ops.sh subscribe erin@example.io | awk '/^token /{print $2}')
TOK2=$(bash /app/list_ops.sh subscribe frank@example.io | awk '/^token /{print $2}')
# grace subscribes but stays unconfirmed; erin/frank confirm out of order
bash /app/list_ops.sh subscribe grace@example.io >/dev/null
bash /app/list_ops.sh confirm frank@example.io "$TOK2"
bash /app/list_ops.sh confirm erin@example.io "$TOK1"
bash /app/list_ops.sh membership