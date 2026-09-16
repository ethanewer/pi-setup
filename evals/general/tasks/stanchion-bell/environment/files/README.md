# Lanternwell Community Clinic website

A small **React 18** information site for a community clinic: four pages
(Home, Services, Book an appointment, Contact) rendered from page-definition
data by a handful of shared components.

## Layout

| path | what |
|------|------|
| `src/App.jsx` | site root component: renders one page from a page definition |
| `src/components/` | shared components (site header, footer, sidebar, card grid, booking form, status dot) |
| `src/data/*.mjs` | page definitions for the four shipped pages |
| `visible/` | the local check suite (functional smoke tests + accessibility gate) |
| `tools/a11y.mjs` | the accessibility check helpers used by the suite |
| `public/img/` | static artwork referenced by the pages |

## Commands

- `npm test` — run the local check suite (vitest + jsdom).
- The repository has a short git history; `git log --oneline` shows it.

## Notes

- The site is checked under **jsdom**, which does not load external
  stylesheets. Styling must be inline (`style="..."`); there is deliberately
  no `styles.css`.
- Network access is disabled in the grading container. Everything the checks
  need (React, jsdom, axe-core, vitest) is installed in `node_modules`.