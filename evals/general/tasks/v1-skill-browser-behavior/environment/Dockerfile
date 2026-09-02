FROM bench-base:ubuntu-24.04

WORKDIR /app

RUN cat > /app/browser_behavior_quiz.txt <<'QUIZ_END'
1. document.getElementById("nav") returns null when no element in the page has that id.
2. A classic <script>...</script> tag in the <head> (no async/defer) blocks rendering while it downloads and executes.
3. On a normal page load, which event fires first: DOMContentLoaded or load?
4. localStorage is shared across all tabs and windows of the same origin.
5. A cross-origin fetch() with a non-simple HTTP method (e.g. PUT) or a custom header triggers a CORS preflight OPTIONS request first.
6. Cookies with SameSite=Strict are never sent on cross-site requests.
7. When a Promise .then() microtask is queued during the same task that queued a setTimeout(cb,0) timer, the timer callback always runs before the microtask.
8. position:fixed positions an element relative to its nearest positioned ancestor.
QUIZ_END
