# escutcheon-stack: bring hand-managed config under Terraform

## Context

`/app/stack` is a service deploy directory for the escutcheon stack. It contains
a `live/` directory holding the configuration files that the running services
read right now. Those files were **created and edited by hand by operations
before Terraform was adopted**, so Terraform has never managed them and holds no
record of them. They are the real, on-disk truth.

Your job is to write one reusable script, `/app/stack/deploy.sh`, that adopts
**any** such deploy directory under Terraform management — the one shipped here
and fresh ones the verifier creates from hidden fixtures.

## Environment

- Terraform `1.9.8` is installed on `PATH` (`terraform version`).
- An **offline filesystem provider mirror** for `hashicorp/local` and
  `hashicorp/null` is pre-baked and configured, so `terraform init`, `terraform
  plan` and `terraform apply` all work with **no network access**.
- `python3`, `base64`, and standard shell tools are available.
- Nothing may be modified outside the snapshot directories you are asked to
  manage.

## The deploy directory shape

Every deploy directory (the shipped one and every hidden one) is a directory
`<SNAP>` whose contents are:

```
<SNAP>/
  live/          one or more plain-text config files, all at the top level
```

The files under `live/` have **arbitrary names and arbitrary content** — no two
fixtures share names or content. Treat them as opaque: do not assume names,
counts, extensions, or contents.

## Deliverable: `/app/stack/deploy.sh`

Write `/app/stack/deploy.sh` with this contract:

- Usage: `deploy.sh <SNAP>` where `<SNAP>` is the absolute or relative path to a
  deploy directory of the shape above.
- It must be a general tool: it must work for **any** deploy directory, driven
  only by its single argument. It must read the actual files present in
  `<SNAP>/live/` at run time, never any hard-coded file name.
- After it runs, the files in `<SNAP>/live/` must be under Terraform management
  such that `terraform init && terraform plan` in `<SNAP>` reports **an empty
  plan (no resources to create, change, or destroy)**.
- It must **not** delete, rename, or rewrite any of the pre-existing `live/`
  files. They already exist on disk and carry the configuration that services
  depend on; adopting them must preserve them byte-for-byte.
- It must add a **second managed resource**: a new file `<SNAP>/deployment.manifest`.

`deploy.sh` may generate any Terraform configuration it needs inside `<SNAP>`
(e.g. a `main.tf`), and it may run `terraform init`, `terraform plan`, and
`terraform apply` in `<SNAP>`. It must exit `0` on success.

## Exact output contract

After a successful `deploy.sh <SNAP>`:

1. **`<SNAP>/deployment.manifest`** exists and contains, exactly, the file names
   of the adopted `live/` files — one per line, in byte-lexicographic order,
   joined by a single `\n`, with **no trailing newline**. (For the shipped
   directory this would be `app.conf\nrouting.conf`.)

2. **`<SNAP>/live/`** files are byte-identical to what they were before the
   script ran.

3. **`<SNAP>/terraform.tfstate`** records the adopted `local_file` resources:
   one for every file in `live/` and one for `deployment.manifest`, each with a
   `filename` matching those paths. No extra managed resources.

4. Re-running `terraform init && terraform plan` in `<SNAP>` produces an empty
   plan.

## Constraints

Do **not** hard-code any fixture path, file name, or file content into
`deploy.sh`. It must be driven only by its `$1` argument and by whatever it
discovers on disk. The verifier executes `/app/stack/deploy.sh` against the
shipped deploy directory and against hidden deploy directories with different
file names, different numbers of files, and different contents.

The shipped `live/` files must remain unmodified in `/app/stack`. Run any
personal smoke tests on a copy, not on `/app/stack/live` in place.
