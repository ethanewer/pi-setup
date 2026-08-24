Your team deploys the webapp in `/app/webapp`, a git repository. Each branch carries the
`config.json` appropriate for one environment: `main` has the **prod** config, and the
branch `feature-eu` has the **eu** (Europe) config. Deployments always go through the
repository's own script `/app/webapp/deploy.sh`. That script copies `config.json` from the
currently checked-out branch into `/srv/app/config.json` and writes a deployment manifest
to `/srv/app/DEPLOYMENT` (lines `branch=<name>` and `commit=<short-hash>`). It is protected
by a CI-style guard: it **refuses** to deploy any branch other than `feature-eu` (try
running it on `main` and you will see the refusal).

Your task: deploy the app for the **eu** environment using the repository's deployment
script, so that afterwards:

1. `/srv/app/config.json` is the eu config (its `env` field equals `"eu"`), and
2. `/srv/app/DEPLOYMENT` contains a line `branch=feature-eu`.

Work in `/app/webapp` using git branch commands (`git branch`, `git checkout`, `git log`,
`git status`) and then run `/app/webapp/deploy.sh`. Do not edit `deploy.sh`, and do not
hand-copy files into `/srv/app` — the deployment script is the only allowed way to write
there.
