A public web app reflects user input inside an HTML page after applying a naive server-side sanitizer. The sanitizer is known to **strip `<script>`-tag content** (opening `<script...>` through closing `</script>`, case-insensitively), but it does **not** encode or strip other HTML.

Your goal: craft an **XSS payload** that, despite that sanitizer, still causes JavaScript `alert(1)` to run in the victim's browser when the app reflects your input.

Write your crafted payload as a single line to `/app/payload.txt`.

Requirements for a correct payload:
- It must trigger JavaScript `alert(1)` via an **HTML event-handler attribute** (e.g. `onerror=`, `onload=`, `onmouseover=`) or a similarly non-`<script>` vector — not by relying on a literal `<script>` tag.
- After the sanitizer runs, the payload must still contain the executable vector: an `alert(` call plus an event handler attribute name.
- Put the payload on one line with no extra explanatory text around it.

The verifier applies the sanitizer logic to your file and checks these properties.