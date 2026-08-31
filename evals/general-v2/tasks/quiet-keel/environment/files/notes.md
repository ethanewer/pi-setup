# Operator notes — quiet-keel batch host

The three batch service accounts were provisioned locked down:

| account       | home                | provisioned shell  |
|---------------|---------------------|--------------------|
| deploy-bot    | /var/lib/deploy-bot | /usr/sbin/nologin  |
| audit-runner  | /var/lib/audit-runner | /bin/false       |
| pipeline-svc  | /var/lib/pipeline-svc | /usr/sbin/nologin |

The runbook entry in `requirement.txt` is authoritative for this change
window: unlock exactly the account it names, with exactly the shell it
names, and record the outcome in `answer.txt`.

Remember: a shell binary being present on disk is not enough — the account
database must report the new shell as the login shell, or the unlock did
not happen.
