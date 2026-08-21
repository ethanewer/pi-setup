# pi-setup-maintenance

A skills-only Pi package. It registers no extensions and no tools, so it adds nothing to
the agent's tool surface and cannot affect a running session.

## `update-pi-setup`

The procedure for updating this machine: Pi itself, the pinned `agent-browser`, and each
hardened fork in `~/pi-setup/forks/`. It exists so an agent asked to "update pi" finds
the pinned, verified path instead of reaching for `pi update` — which bypasses
`lib/versions.json`, gets silently reverted by the next install, and is reported as drift by
`bin/pi-setup-doctor`.

It covers where the version pins live, how to read a changelog for breaking changes
before bumping, how `bin/pi-setup-vendor` re-vendors a fork onto a newer upstream and
what to re-review afterwards, why `agent-browser` is deliberately not tracked to latest,
the verification commands, and how to roll back.

The skill is the documentation; this README only explains why the package exists.
