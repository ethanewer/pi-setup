`nginx` is already installed on this system. There is a web root `/app/www` containing `index.html`.

Create an nginx configuration file `/app/nginx.conf` that, among other things:

1. Sets `worker_processes 4;`.
2. Defines an `events { worker_connections 256; }` block.
3. Uses an absolute `pid` path under `/tmp` (e.g. `pid /tmp/nginx_super.pid;`).
4. Defines an `http { ... }` block containing a `server { ... }` that listens on TCP port `8092` and serves static files from `root /app/www;`.

Use absolute paths for any `pid`, `error_log`, and `access_log` directives (standalone config, no prefix directory).

Then **start nginx** with that config:

```
nginx -c /app/nginx.conf
```

After starting it, verify that the process is being supervised as intended: there should be one nginx **master** process and your configured number of **worker** processes. Inspect the running processes with e.g. `ps -axo pid,args | grep nginx` (worker entries appear as `nginx: worker process`).

Write `/app/supervision.txt` as exactly one line:

```
running_workers=<N>
```

where `<N>` is the number of nginx worker processes you observed actually running. Leave nginx running. The evaluator will start nothing itself: it will read `worker_processes` from `/app/nginx.conf`, count the nginx master and worker processes currently running, and check that your report matches the configured worker count.