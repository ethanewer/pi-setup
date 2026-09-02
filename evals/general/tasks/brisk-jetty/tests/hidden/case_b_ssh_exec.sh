#!/bin/bash
# Hidden case B — ssh_host_exec.sh argument handling.
# With no argument it must print a usage message and return non-zero; with an
# arbitrary remote command it must run that command in the guest and print the
# exact output.
set -u

# 1) no argument -> usage + nonzero
bash /app/ssh_host_exec.sh >/tmp/case_b.out 2>/tmp/case_b.err
rc=$?
[ "$rc" -ne 0 ] || { echo "case_b: no-arg invocation should be nonzero" >&2; exit 1; }
grep -qiE 'usage|command' /tmp/case_b.err || { echo "case_b: no usage text on stderr" >&2; exit 1; }

# 2) arbitrary remote command -> exact output over the forwarded port
OUT=$(bash /app/ssh_host_exec.sh "printf 'CASE-B-%s-<%s>' seven relay" 2>/dev/null)
[ "$OUT" = "CASE-B-seven-<relay>" ] || { echo "case_b: arbitrary command output wrong: '$OUT'" >&2; exit 1; }

# 3) a meaningful in-guest inspection (hostname persisted by the console drive)
HN=$(bash /app/ssh_host_exec.sh "cat /etc/hostname" 2>/dev/null | tr -d '[:space:]')
[ "$HN" = "nysa-relay-appliance" ] || { echo "case_b: guest hostname via ssh wrong: '$HN'" >&2; exit 1; }

exit 0
