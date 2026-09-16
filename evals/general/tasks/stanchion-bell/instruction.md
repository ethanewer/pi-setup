# Lanternwell Clinic: make the site accessible

You are the new frontend developer for **Lanternwell Community Clinic**. The
site was recently flagged by an accessibility audit, and the practice board
wants the problem gone before the March intake. Your job is to remediate the
React app at `/app/src/` so every page of the site conforms to the grading
contract below — including pages the audit team has not shown you.

## Environment

- **Node 22** with React 18, `jsdom`, `axe-core`, `vitest` and
  `@testing-library/react` installed under `/app/node_modules`. Network is
  disabled; do not attempt to install anything.
- `/app` is a **git repository** with a short history (`git log --oneline`).
  Keep your changes inside `/app`; never touch `/tests` or `/solution`.
- The site is a React app: `src/App.jsx` is the root component that renders
  one page from a page definition; shared components live in
  `src/components/`; the four shipped pages' data lives in `src/data/`.
  There is deliberately no stylesheet — pages are checked under jsdom, which
  does not load external CSS, so any styling must be **inline**.
- `npm test` runs the local check suite for the four shipped pages (a
  functional smoke test plus the accessibility gate). A correct remediation
  makes it green.

## The grading contract

The verifier re-renders pages from your code and enforces **all** of the
following on every page: the four pages shipped in `src/data/` **and three
unseen pages** rendered from fresh page data by the same components. A single
page-specific patch will not generalize.

1. **axe-core (WCAG A/AA + best practice).** Zero violations of **moderate,
   serious or critical** impact. Two rules are excluded from the run —
   `color-contrast` and `target-size` — because they need real browser
   geometry that jsdom cannot provide; the colour-only contract (5) replaces
   them.
2. **Skip link.** The *first focusable element* on every page must be a link
   whose href targets an element with `id="main-content"` and whose visible
   text mentions "skip".
3. **Focus order.** A keyboard user must reach the **main content before the
   supporting sidebar column**: the `main` landmark must precede the
   `complementary` landmark in the DOM, and at least one focusable control
   must live in each region.
4. **Live region.** The clinic announcement shown at the top of every page
   must be announced to assistive technology: it must be inside an element
   with `role="status"` or an `aria-live` attribute.
5. **No colour-only state.** Every status indicator whose meaning is conveyed
   by colour must also expose its state as accessible text (or
   `aria-label`): the state word — `open`, `busy` or `closed` — must appear,
   so the information survives colour-blindness and screen-reader output.
6. **Form labels.** Every form control (`input`, `select`, `textarea`) must
   have an **explicitly associated label**: a wrapping or `for`-associated
   `<label>` element, or a non-empty `aria-label`/`aria-labelledby`.
   Placeholder text alone is not a label.
7. **Heading hierarchy.** Exactly **one `h1`** per page; heading levels must
   increase by at most one as the document proceeds — no skipped levels in
   either direction.
8. **Images.** Every image must carry appropriate alternative text: an
   informative `alt` for content images (the page data supplies one) and an
   explicit empty `alt=""` for anything purely decorative.

## Deliverable

The remediated app under `/app/src/` (the root component must keep its
default export: a component that renders a page from a page definition, as
the verifier imports it directly). Do not change the data files or the check
tooling to mask problems — the verifier brings its own page data and its own
copy of the checks, and runs them against your components.

When you believe the site conforms, run `npm test` and verify every local
check passes before finishing.