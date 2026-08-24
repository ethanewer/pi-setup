# Install a package from a custom index URL

`/app/repo/` contains a local Python package:

- A prebuilt wheel: `/app/repo/myprobe-0.1.0-py3-none-any.whl`
- A **PEP 503 "simple" index page**: `/app/index.html` describing it.

The page looks like this:

```html
<!DOCTYPE html>
<html><head><title>Simple Index</title></head>
<body>
<a href="./myprobe-0.1.0-py3-none-any.whl">myprobe-0.1.0-py3-none-any.whl</a><br>
</body></html>
```

Your task:

1. Start a `python3 -m http.server` serving `/app` (pick a free port number such as 8765, run it in the background).
2. Make pip install **from that index** with
   `--index-url http://127.0.0.1:8765` so the package is resolved from your
   index, **not** from PyPI:

   ```
   pip install --index-url http://127.0.0.1:8765 myprobe
   ```

3. Verify the install by importing and calling it:

   ```python
   import myprobe
   print(myprobe.probe())   # -> "probe ok"
   ```

   Then write exactly that output string to `/app/out.txt` (with a trailing newline).

When done, confirm `/app/out.txt` exists and contains `probe ok`.