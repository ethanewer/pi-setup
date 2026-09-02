#!/usr/bin/env bash
# Case 3: unsubscribe/leave removes an address before it is ever confirmed.
set -u

bash /app/list_ops.sh subscribe dave@example.org >/dev/null
bash /app/list_ops.sh unsubscribe dave@example.org
# leaving an unconfirmed (pending) address must leave an empty list
bash /app/list_ops.sh membership