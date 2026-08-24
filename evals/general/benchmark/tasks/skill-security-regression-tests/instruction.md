A Flask application in `/app/webapp.py` has an endpoint `/greet?name=<name>` that reflects the
`name` parameter into an HTML page, making it vulnerable to reflected XSS.

1. Write a security regression test at `/app/test_xss_regression.py` using `pytest` that:
   - starts the app with Flask's test client,
   - sends `GET /greet?name=<script>alert(1)</script>`,
   - asserts the response body does NOT contain the raw string `<script>alert(1)</script>`,
   - asserts it DOES contain the escaped form (`&lt;script&gt;` or equivalent).
2. Fix the vulnerability in `/app/webapp.py` (escape the user input properly).
3. Ensure `python3 -m pytest /app/test_xss_regression.py` passes.

The final state must have both files present and the test passing.
