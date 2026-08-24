# Parse a PEP 503 package index

`/app/index.html` is an HTML page in the format of a **PEP 503 "simple" package
index** (the simple repository protocol used by `pip`). It announces one package
named `demo`, and it links to every downloadable distribution archive for that
package, e.g.:

```
<a href="./demo-0.9.0-py3-none-any.whl">demo-0.9.0-py3-none-any.whl</a>
```

Each such link's filename encodes the distribution name and its version in the form
`demo-<version>-py3-none-any.whl` (so you can also scan the page for those filenames).

Your task: determine the **newest (highest) version of `demo`** that the index
announces, and write exactly that version string (e.g. `1.2.0`) to
`/app/version.txt`, followed by a newline.

Use the standard PEP 503 semantics: compare versions numerically, component by
component (`major.minor.patch`), so `1.2.0` is newer than `1.0.0`, which is newer
than `0.9.0`.

When done, confirm `/app/version.txt` contains only the newest version string.