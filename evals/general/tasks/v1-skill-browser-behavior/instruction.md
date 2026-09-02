Answer the following questions about **browser / web-platform behavior**. You do not need
to run a browser; answer from knowledge of how browsers behave. The questions are also
reproduced in `/app/browser_behavior_quiz.txt`.

For each question answer exactly `true` or `false`, except question 3 which asks you to
pick one of two named values. Write the answers as a JSON file at `/app/browser_answers.json`
in this exact shape (keys q1..q8, values all lowercase strings):

```json
{"q1":"true","q2":"true","q3":"DOMContentLoaded","q4":"true","q5":"true","q6":"true","q7":"false","q8":"false"}
```

Questions:
1. `document.getElementById("nav")` returns `null` when no element in the page has that id.
2. A classic `<script>…</script>` tag placed in the `<head>` (with neither `async` nor
   `defer`) blocks page rendering while the script is downloaded and executed.
3. On a normal page load, which event fires first: `DOMContentLoaded` or `load`?
4. `localStorage` is shared across all tabs and windows of the same origin.
5. A cross-origin `fetch()` that uses a non-simple HTTP method (for example `PUT`) or a
   custom header triggers a CORS preflight `OPTIONS` request before the actual request.
6. Cookies set with `SameSite=Strict` are never sent on cross-site requests.
7. When a Promise `.then()` microtask is queued during the same task that queued a
   `setTimeout(cb, 0)` timer, the timer callback always runs before the microtask.
8. In CSS, `position: fixed` positions an element relative to its nearest positioned
   ancestor.

Write your JSON answers to `/app/browser_answers.json` (exactly these 8 keys).
