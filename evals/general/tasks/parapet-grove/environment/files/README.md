# parapet intake service

parapet collects metric payloads from instrumented hosts, validates each
payload against the allowed source list and a size cap, and forwards accepted
payloads to the analytics lake.

## Releases

- `1.0.2` — currently deployed in every environment.
- `2.0.1` — RE-1142 fix: metric payloads from edge gateways
  (`"source": "edge"`) are rejected by 1.0.2 and must be accepted, and the
  payload cap is raised for gateway batches. This is the fix that needs to go
  out.

## Deploying

Use the deploy tool:

```
/app/deploy/deploy.sh <env-config.json> <release-dir>
```

The environment registry lives in `/app/deploy/envs/` — read the README there
and both environment config files before deploying anything.

## Layout

- `/app/releases/<version>/` — release bundles (service script, config, VERSION)
- `/app/deployed/<environment>/` — live install of each environment
- `/app/deploy/` — deploy tool and environment registry