# First-party skills

Skills that belong to this setup itself, installed into the agent directories
(`~/.pi/agent/skills/` and `~/.pi/agent-wf/skills/`) by `install.sh`. They are not Pi
packages: no `package.json`, no entry in `settings.json`, nothing in `vendor.json`.
That is deliberate — these three used to be skills-only packages under `forks/`, but a
skill is not a package and `forks/` is the path for packages (hardened forks and the
first-party extensions), with patch and provenance machinery that a pure skill does not
use. The lean `p` entrypoint runs `--no-skills`, so none of these load there — the same
as when they were packages that profile never listed.

Editing a skill: change it here, run `./install.sh`, done. `bin/pi-setup-doctor` checks
the installed copies against this directory. Do not add unrelated skills next to these;
`install.sh` only manages the three named directories and leaves anything else in
`~/.pi/agent/skills/` alone.

## agent-browser-cli

Teaches the agent to drive the `agent-browser` CLI that `install.sh` installs and
pins — the core open/snapshot/act/re-snapshot loop plus the live-web behavior rules
that matter most: complete bot checks by reading them, wait out "checking your browser"
interstitials instead of refreshing, and honor `Retry-After` on 429s. The skill points
at `agent-browser skills get core` for the full reference, which the CLI serves matched
to the installed version.

It exists because the browser-bench eval (`evals/browser/` on the `browser-eval`
branch) found that a CLI plus one skill — zero additions to Pi's tool surface —
matched or beat every extension arm on outcome at roughly half the browser
calls and tokens, on both models tested. `agent-browser` was chosen over
`@playwright/cli` because it never fell below 0.93 on either model (the Playwright
CLI's rate-limit handling collapsed on one of them) and because it is the engine the
setup already installs and pins. Two things the fixture could not measure and that
motivated the behavior rules anyway: live-web captchas are driven by IP reputation,
automation signals, and profile state, not by which code drives Chrome; what an agent
can control is handling. See that branch's `evals/browser/REPORT.md` for the full
writeup and raw results, and the [README](../README.md) Browser automation section for
the opt-in back to the native tool (`PI_SETUP_BROWSER_TOOL=1`).

## update-pi-setup

The procedure for updating this machine: Pi itself, the pinned `agent-browser`, and
each hardened fork. It exists so an agent asked to "update pi" finds the pinned,
verified path instead of reaching for `pi update` — which bypasses `install.sh`, is
silently reverted by the next install, and is reported as drift by
`bin/pi-setup-doctor`.

## unslop

Adapted from [cursor/plugins](https://github.com/cursor/plugins) with the "Adding
soul" section removed and the process reduced to three steps. It tells the model to
cut AI tells from any writing and to always apply, so every model-facing string in
this repository is something the skill itself would flag if it regresses.
