# loghost -- ingress log collector

Collects request logs from the fleet.  Layout:

    ingress/     rotated request/response logs (junk once rotated)
    app/web/tmp/ transient scratch files (junk)
    var/crash/   core dumps (junk)
    config/      service configuration (real)
    archive/     kept archive data (real)

The cleanup policy in `policy.json` defines the junk rules and the budget.
`RESTORE.manifest` lists the restored trees that must be kept byte-for-byte
(content, permissions, ownership, timestamps).  Never touch anything at or
below a listed path -- even when it lives inside a directory that otherwise
looks like junk.  Never create files in the root, and never remove the policy
or the manifest.
