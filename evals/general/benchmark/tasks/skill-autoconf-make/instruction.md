# Building a project with `make`

`/app/pkg/` contains a configured buildable project. A `configure` step (already done) produced `config.mk` carrying a `VERSION` value. The project provides:

- `Makefile` — declares a target `all` that depends on `config.mk` and `build.py`, and produces a file `built/output.txt`.
- `build.py` — a small script that reads `config.mk` (a line of the form `VERSION=<value>`) and writes `built/output.txt` containing `APP_VERSION=<value>` plus a newline.
- `config.mk` — the configuration key/value file.

Your job is to build the project by running the standard Autotools/`make` command. Once built, the Makefile's dependency chain causes `built/output.txt` to be created.

## Task

From inside `/app/pkg/`, run `make` (with no extra targets) so that the build **completes** and the artifact `/app/pkg/built/output.txt` is produced.

After the run, `/app/pkg/built/output.txt` must exist and contain exactly:

```
APP_VERSION=<VERSION>
```

where `<VERSION>` is the value present in `/app/pkg/config.mk`. For example, if `config.mk` contains `VERSION=3.11`, then `built/output.txt` must contain `APP_VERSION=3.11`.