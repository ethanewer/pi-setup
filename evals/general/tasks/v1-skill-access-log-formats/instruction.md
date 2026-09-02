# Apache access-log parsing

`/app/access.log` contains web-server access log lines in the **Apache Common Log Format (CLF)**:

```
host ident authuser [date] "METHOD request HTTP/version" status bytes
```

For example:

```
127.0.0.1 - frank [10/Oct/2000:13:55:36 -0700] "GET /apache_pb.gif HTTP/1.0" 200 2326
```

Parse **every** line of `/app/access.log` and compute the following three statistics:

1. `status_200_count` — the total number of requests that returned HTTP status `200`.
2. `distinct_ips_count` — the number of distinct client host/IP values across all lines.
3. `paths_sorted` — the sorted (ascending lexicographic) list of distinct requested resource paths. The path is the middle token of the quoted request line (e.g. for `"GET /apache_pb.gif HTTP/1.0"` the path is `/apache_pb.gif`).

Write the result to `/app/answer.json`:

```json
{
  "status_200_count": 3,
  "distinct_ips_count": 4,
  "paths_sorted": ["/apache_pb.gif", "/index.html", "/submit"]
}
```

Fill in the three values by parsing `/app/access.log` yourself. The exact values depend on the file contents; the json above is only a format example.