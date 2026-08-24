# JavaScript XSS analysis

Read `/app/page.html`. It is a small server-rendered HTML page that embeds JavaScript which reads the visitor's `q` URL query parameter and writes it into the page.

Determine whether this code is vulnerable to a **cross-site scripting (XSS)** attack, and if so, describe the fix concisely.

Write your judgment to `/app/answer.json` with exactly this shape:

```json
{
  "vulnerable": "yes",
  "issue": "<one short phrase naming the cause>",
  "fix": "<one short phrase describing the fix>"
}
```

Rules:
- `vulnerable` must be exactly `"yes"` or `"no"` (in the case of this task it is `"yes"`).
- `issue` must be a short lowercase-ish phrase mentioning the root cause: that **untrusted user input is interpolated into HTML/JS output without escaping**.
- `fix` must be a short phrase mentioning the remedy: **encode/escape the user input (HTML-escape) before writing it into the output**, or safely neutralize it.

Keep each phrase under 200 characters. The grader checks that you identified the vulnerability and the correct class of fix; exact wording is not required.