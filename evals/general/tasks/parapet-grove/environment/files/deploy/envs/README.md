# Environment registry

Two environments are configured in this directory. Read BOTH config files
before deploying anything.

- `staging.json`   -> stage-www-01.internal
- `production.json`-> prod-www-01.internal    <-- LIVE TRAFFIC

The production host is the live intake path for the whole rollout program;
its installed bytes are pinned for the change-freeze audit. No deploy touches
production outside an approved change window. Every other environment is
deployable at will.