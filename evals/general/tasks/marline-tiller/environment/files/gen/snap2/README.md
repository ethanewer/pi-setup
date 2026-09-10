# marline-lib

A small React component library: three form controls that share one design
principle — **every component supports both a controlled mode (the caller owns
the value via a `value` prop and hears about changes through `onChange`) and an
uncontrolled mode (the component owns it, seeded by `defaultValue`)**.

The library is consumed as a **build artifact**: `npm run build` must produce a
single ESM module (`dist/marline-lib.mjs`) plus TypeScript declarations for
every public export under `dist/**.d.ts`. `npm test` runs the component test
suite under vitest with a jsdom environment.

## Components

### Counter — `Counter`

Stepper with two buttons and a live count display.

| prop            | type     | default | meaning                                        |
|-----------------|----------|---------|------------------------------------------------|
| `label`         | `string` | —       | accessible group label                         |
| `min`           | `number` | `0`     | inclusive floor                                |
| `max`           | `number` | `100`   | inclusive ceiling                              |
| `step`          | `number` | `1`     | increment / decrement delta                    |
| `value`         | `number` | —       | **controlled**: renders this, clamped          |
| `defaultValue`  | `number` | `0`     | **uncontrolled**: initial internal value       |
| `onChange`      | `(next: number) => void` | — | fired on every committed change   |
| `disabled`      | `boolean` | `false` | blocks the controls                            |

Rules:

- The displayed value is the current value **clamped into `[min, max]`** on
  every render. `step` is applied on top of the clamped current value, then the
  result is clamped again, so the counter can never leave the range.
- **Controlled mode** is active when `value` is a number. The component never
  keeps its own value: the display always mirrors the clamped prop, and a click
  reports `clamp(current ± step)` through `onChange`. External changes to
  `value` (including out-of-range values) are reflected immediately.
- **Uncontrolled mode**: the internal value starts at `defaultValue`, steps
  update it, and `onChange` reports what actually happened.
- A `disabled` counter ignores clicks and renders both buttons with a
  `disabled` attribute.

Markup contract: a `role="group"` wrapper labelled by `label`, containing a
`button[aria-label="decrement"]`, an `output[data-testid="counter-value"]`
holding the decimal string of the displayed value, and a
`button[aria-label="increment"]`.

### QuantityInput — `QuantityInput`

A numeric text box. While typing, an uncommitted **draft** is held; a commit
happens on **Enter or blur**, and arrow keys step from the committed value.

| prop            | type     | default | meaning                                        |
|-----------------|----------|---------|------------------------------------------------|
| `label`         | `string` | —       | `aria-label` on the input                      |
| `min`           | `number` | `0`     | inclusive floor                                |
| `max`           | `number` | `100`   | inclusive ceiling                              |
| `step`          | `number` | `1`     | arrow-key delta                                |
| `value`         | `number` | —       | **controlled**: rendered text mirrors this     |
| `defaultValue`  | `number` | `0`     | **uncontrolled**: seed for internal state      |
| `onChange`      | `(next: number) => void` | — | fired on every successful commit   |
| `disabled`      | `boolean` | `false` | disables the input and the keys                |

Rules:

- **Arrow keys** compute the next value from the current committed value
  (`current ± step`, clamped) — a half-typed draft does **not** become the base
  for stepping, and stepping discards it.
- **Commits** parse the draft as a decimal number. A draft that is not a finite
  number reverts the box to the last committed value and fires **nothing**; a
  valid draft is clamped into `[min, max]` and committed.
- Controlled mode mirrors the clamped prop and never mutates its own copy;
  clicking arrows or committing still reports through `onChange` and the text
  only changes when the caller updates `value`.

Markup contract: a single `<input type="text" inputMode="numeric">` carrying
`aria-label={label}`, whose `value` attribute is the decimal string of the
displayed number.

### TagPicker — `TagPicker`

A chip multi-select over a fixed option list.

| prop            | type                    | default  | meaning                              |
|-----------------|-------------------------|----------|--------------------------------------|
| `options`       | `TagOption[]`           | —        | `{ id: string, label: string }` list |
| `value`         | `string[]`              | —        | **controlled**: current selection    |
| `defaultValue`  | `string[]`              | `[]`     | **uncontrolled**: initial selection  |
| `onChange`      | `(ids: string[]) => void` | —       | fired on every toggle                |
| `disabled`      | `boolean`               | `false`  | ignores clicks                       |
| `emptyLabel`    | `string`                | `'Nothing selected'` | summary text when empty |

Rules:

- Clicking a chip toggles it in or out of the selection.
- **`onChange` always receives a fresh array** — never the caller's `value`
  array, and the caller's array is never modified behind its back. In
  uncontrolled mode the internal state is also replaced, never spliced in
  place, so re-renders always reflect the toggle.
- Controlled mode derives the selection from the `value` prop, so the visible
  selection changes when — and only when — the caller updates `value`.

Markup contract: a `div[data-testid="tagpicker"]` containing a
`span[data-testid="tag-summary"]` (either `emptyLabel` or
`"<n> selected"`), and one `<button role="option" data-tag-id="{id}">` per
option, with `aria-selected` and class `selected` reflecting membership.

## Scripts

| script                | effect                                                |
|-----------------------|--------------------------------------------------------|
| `npm run build`       | `vite build` (library mode, ESM) then `tsc` declarations |
| `npm test`            | vitest, jsdom environment, `tests/**`                  |
| `npm run typecheck`   | `tsc --noEmit`                                         |
