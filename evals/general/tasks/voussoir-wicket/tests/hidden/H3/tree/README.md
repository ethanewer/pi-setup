# relay-farm -- message relay & gateway services

Relays messages between fleets.  Layout:

    services/gateway/  gateway logs, caches and staging junk
    var/crash/         core dumps (junk)
    var/hold/          quarantined messages awaiting review (RESTORE.manifest)
    var/lib/           live databases (real -- keep them)
    config/            configuration (real)

The cleanup policy in `policy.json` defines the junk rules and the budget.
`RESTORE.manifest` lists the restored trees that must remain byte-for-byte
identical (content, permissions, ownership, timestamps).  Never remove the
policy or the manifest, and never create files inside the root.
