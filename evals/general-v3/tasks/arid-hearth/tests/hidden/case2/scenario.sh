#!/usr/bin/env bash
# Case 2: a wrong token must NOT confirm; the correct token then must.
set -u

TOK=$(bash /app/list_ops.sh subscribe carol@example.net | awk '/^token /{print $2}')
# before any confirmation, carol must not be active
before=$(bash /app/list_ops.sh membership)
[ -z "$before" ] || exit 91

# a wrong token must not promote carol
bash /app/list_ops.sh confirm carol@example.net WRONGTOKEN 2>/dev/null && exit 92 || true
mid=$(bash /app/list_ops.sh membership)
[ -z "$mid" ] || exit 93

# the correct token must promote carol
bash /app/list_ops.sh confirm carol@example.net "$TOK" 2>/dev/null || exit 94
bash /app/list_ops.sh membership