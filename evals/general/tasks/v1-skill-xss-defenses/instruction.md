In `/app` there is a Python module `render.py` that exposes a function:

```python
def render_html(user_input):
    return "<div>" + user_input + "</div>"
```

This is vulnerable to **stored/reflected XSS**: if `user_input` contains HTML/script (e.g. `<script>alert(1)</script>`), it is inserted raw and a browser would execute it.

Fix `/app/render.py` so its `render_html(user_input)` function is **defense-in-depth against XSS by HTML-escaping** all HTML-special characters in the user input before embedding it in the `<div>`. Use Python's standard `html` module (`html.escape`) — do not install packages. The returned HTML must never contain a raw `<`, `>`, or `&` that comes from user input; those must be escaped as entities (e.g. `&lt;`, `&gt;`, `&amp;`). Keep the outer `<div>` wrapper.

Your edited `/app/render.py` will be imported and exercised with dangerous inputs, and the reward depends on it escaping them correctly.