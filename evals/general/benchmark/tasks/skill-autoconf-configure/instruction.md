# Running `configure` to produce build config

`/app/pkg/` contains a small Autotools-style source package. It contains a top-level shell-script **`configure`** whose job (like the GNU Autoconf-generated `configure` script) is to inspect the requested build options and generate a build-configuration header `defs.h` in the **current working directory**.

Read `/app/pkg/configure` to see how it parses arguments. It accepts these two `--name=value` style options:

- `--with-feature=<NAME>` sets the macro `WITH_FEATURE`
- `--enable-opt=<LEVEL>` sets the macro `ENABLE_OPT`

It writes `defs.h` with `#define` lines reflecting the selected values.

## Task

From inside `/app/pkg/`, run the `configure` script so that it produces `/app/pkg/defs.h` with these two settings:

- `WITH_FEATURE` = `blas`
- `ENABLE_OPT` = `64`

In other words, run `./configure` with the options that produce exactly that configuration, e.g.:

```
cd /app/pkg
./configure --with-feature=blas --enable-opt=64
```

After running it, confirm `/app/pkg/defs.h` exists and contains the two `#define` macros named above with the values `blas` and `64`. (Exactly one invocation of `./configure` with the specified option values is all that is needed.)