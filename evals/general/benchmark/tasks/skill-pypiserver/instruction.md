# Install a package through a local pypiserver

**pypiserver** is a minimal, standalone package that exposes a bare-bones PyPI-compatible index. This environment has it installed via pip.

A release of the tiny package `pipysample` (version `1.0.0`) is already placed at:

```
/app/packages/pipysample-1.0.0-py3-none-any.whl
```

`pipysample` provides:
- `pipysample.greet(name)` → returns the string `"hello " + name`
- `pipysample.VALUE` → the integer `41`

Your job is to serve this package **through pypiserver** and then install it with pip **from that server**, so that the package becomes importable in the environment.

Concretely:

1. Start pypiserver in the background, serving the package directory `/app/packages` on port `8080`, with authentication disabled (so anonymous read/install works). A typical command is:

   ```
   python3 -m pypiserver run -p 8080 -a . -P . /app/packages &
   ```

   (The installed pypiserver is v2+, so use the `run` subcommand; the package
   directory is a positional argument. `-a . -P .` disables authentication, so
   anonymous read/install works.)

   (Wait a couple of seconds for it to come up before continuing.)

2. Use `pip` to install `pipysample` **from the pypiserver index URL**:

   ```
   pip install "pipysample" --index-url http://localhost:8080/simple/
   ```

   You may need a separate pip `--no-build-isolation` flag on very new pip versions, but it should not normally be required.

3. Write a short Python snippet (or reuse pip's completion) that imports `pipysample` and writes `/app/proof.txt` containing exactly one line:

   ```
   {greet_result};{VALUE_plus_1}
   ```

   where `greet_result` is `pipysample.greet("world")` (so `hello world`) and `VALUE_plus_1` is `pipysample.VALUE + 1` (so `42`). Example: `hello world;42`.

The verifier imports `pipysample` (it should be importable if your pip install went through the server) and checks the `/app/proof.txt` line.

## Note
- The chosen port 8080 must be free. Do not start another server on it.
- `-a .` disables authentication; without it pypiserver may require credentials for downloads.