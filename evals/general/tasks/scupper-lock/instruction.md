# scupper-lock — an accessible React 18 data-table component

## What you build

A generic, accessible **React 18 data table component** written from scratch in
a pre-provisioned React workspace: column sorting, row filtering, selection in
three modes (none / single / multiple, controlled and uncontrolled), grid
keyboard navigation, and an API-reference document for it.

The component is judged by an independent verifier that renders it under
jsdom with `@testing-library/react`, exercises it through hidden prop/data
fixtures (more datasets, more prop combinations than the visible suite), and
strict type-checks hidden consumer code against its exported prop types.

The implementation details — internal state structure, hooks usage, module
layout, styling — are yours to choose. What is fixed is the behavior contract
and the public API names below.

## Environment

- `bench-base:node-22` — Node 22.23.2, npm on `PATH`.
- `/app` already contains a provisioned React workspace. Do not modify
  anything already in it except by adding your deliverables:
  - `package.json` — pinned deps; `npm run test` = `vitest run`,
    `npm run typecheck` = `tsc --noEmit -p tsconfig.json`
  - `tsconfig.json` — strict TypeScript config for the workspace
  - `vitest.config.ts` — shared jsdom test configuration
  - `visible/visible.test.tsx` — the visible test suite (runs under jsdom)
  - `node_modules/` — react 18.3.1, react-dom, @testing-library/react,
    @testing-library/user-event, jsdom, vitest, typescript, @types/react
- The container has **no network access**. Everything you need is already in
  the image; do not attempt to install anything.
- `/tests` holds the hidden generalization fixtures and `/solution` holds the
  reference materials. Do not read or modify either; they are read-only and
  mount nothing your deliverables depend on.

## Deliverables

Create exactly two files:

1. **`/app/DataTable.tsx`** — the component module. It must export named
   `DataTable`, `DataTableProps`, `ColumnDef`, `SortState` and
   `SortDirection`, and must compile under the workspace's strict
   `tsconfig.json`. You may add helper modules of your own beside it, but the
   component and its public types must all importable from
   `/app/DataTable.tsx`.
2. **`/app/DataTable.md`** — an API reference for the component. It must
   mention `DataTable` and document every required prop and exported type by
   the exact names listed in the Public API section, plus the behavioral
   rules for sorting, filtering, selection and keyboard navigation.

## Public API (required names, exact spellings)

`DataTable` is generic over the row type `T`.

- `SortDirection = 'asc' | 'desc'`
- `SortState = { key: string; direction: SortDirection }`
- `ColumnDef<T>`:
  - `key: string` — stable identity, used for sorting and `aria-sort`
  - `label: string`
  - optional `sortable?: boolean`, `align?: 'start' | 'center' | 'end'`,
    `getValue?: (row: T) => string | number | null | undefined` (raw value
    used for sorting and filtering; falls back to `row[key]`),
    `render?: (row: T, index: number) => React.ReactNode`,
    `headerClassName?: string`, `cellClassName?: string`
- `DataTableProps<T>`:
  - `data: T[]`, `columns: ColumnDef<T>[]`,
    `getRowId: (row: T, index: number) => string`
  - `ariaLabel?: string` (default `"Data table"`),
    `className?: string`,
    `getRowClassName?: (row: T, index: number) => string | undefined`
  - `selectionMode?: 'none' | 'single' | 'multiple'` (default `'none'`)
  - `selectedIds?: string[]` — the controlled selection
  - `defaultSelectedIds?: string[]` — the uncontrolled initial selection
  - `onSelectionChange?: (ids: string[]) => void`
  - `sortable?: boolean` (default `true`; per-column default), 
    `defaultSort?: SortState`, `onSortChange?: (sort: SortState) => void`
  - `searchable?: boolean` (default `true`), `defaultFilter?: string`,
    `filterText?: string` (controlled), `onFilterChange?: (text: string) => void`
  - `navigable?: boolean` (default `true`)

You may add further props of your own; the list above is the minimum surface
that hidden consumers rely on.

## Behavior contract

### Root markup, roles, styling hooks

- The root element carries `role="grid"` when `navigable` (cells are
  `role="gridcell"`) and `role="table"` otherwise (cells `role="cell"`); its
  `aria-label` is the `ariaLabel` prop.
- One header row (`role="row"` with `role="columnheader"` cells, one per
  column) comes first, then one data row per *visible* record in sorted
  display order.
- Sortable columns render a `<button>` in the header whose accessible name is
  the column label; non-sortable columns render plain header text. Sortable
  headers carry `aria-sort` = `"ascending"` / `"descending"` for the column
  currently sorted and `"none"` otherwise; non-sortable headers carry no
  `aria-sort`.
- `className` applies to the root; `getRowClassName` values land on the data
  rows; `headerClassName` / `cellClassName` on the header / cells of the
  columns that define them; `align` becomes `text-align` on the header and
  cells of that column.

### Sorting

- Clicking a sortable header toggles that column `asc` → `desc` → `asc` and
  fires `onSortChange({ key, direction })` with the new state. Clicking a
  different column starts it ascending. `defaultSort` pre-applies the initial
  state (visible in `aria-sort` from the first render).
- Comparison: numbers numerically; strings case-insensitively in code-unit
  order (lowercase first); `null` / `undefined` always sort last in both
  directions; rows with equal keys keep their original relative order
  (stable sort).

### Filtering

- When `searchable` is true, a `type="search"` input with
  `aria-label="Filter rows"` is rendered above the table. A row is hidden
  unless at least one of its columns' raw values (per `getValue`, else
  `row[key]`) contains the query as a case-insensitive substring; an empty
  query shows everything.
- Uncontrolled: typing updates the visible rows and fires `onFilterChange`.
  Controlled (`filterText`): the prop drives both the input value and the
  visible rows; typing fires `onFilterChange` only and does not change state.
- Filtering never changes the selection itself and never fires
  `onSelectionChange`.

### Selection

- Multiple mode: each row has a checkbox with
  `aria-label="Select row ${id}"` (`aria-checked` reflects checked state), and
  the header carries a select-all checkbox `aria-label="Select all rows"`
  whose `aria-checked` is `"true"` / `"mixed"` / `"false"` depending on
  whether all / some / none of the *visible* rows are selected. Select-all
  selects or clears the visible rows only; rows hidden by the filter keep
  their state.
- Single mode: no checkboxes. Clicking a row selects only that row and fires
  `onSelectionChange`; clicking the already-selected row is a no-op and fires
  nothing.
- Every data row carries `aria-selected` = `"true"` / `"false"` whenever
  `mode !== 'none'`.
- The array passed to `onSelectionChange` always contains all selected ids in
  `data` order (position in `data`), not in display order.
- Controlled vs uncontrolled: if `selectedIds` is provided the checkboxes /
  `aria-selected` mirror that prop and interactions only report through
  `onSelectionChange`; otherwise `defaultSelectedIds` seeds internal state
  that the UI reflects immediately after each toggle.

### Keyboard navigation (when `navigable`)

- Exactly one data row is tabbable (`tabindex="0"`, the others `-1`),
  initially the first visible row, and the cursor does not reset when the
  user navigates. When the focused row is hidden by a filter or disappears,
  the cursor moves back to a visible row.
- On a focused row: ArrowDown / ArrowUp move one row (clamped at the
  edges), Home / End jump to first / last row, and Space / Enter toggle the
  focused row's selection exactly as an equivalent mouse action would.

## How to check your work

```bash
cd /app
npx vitest run          # runs visible/visible.test.tsx under jsdom
npm run typecheck       # strict tsc over the workspace
```

The visible suite covers the essentials of every rule above. The hidden
fixtures generalize them: other datasets, controlled selection and filter,
non-navigable rows, numeric sorting with nulls, custom renderers and class
hooks, and two consumer files strict type-checked against the exported prop
types.

## Constraints

- Do not modify any provided file under `/app`; only add your two
  deliverables (plus optional helper files).
- Do not install anything, and do not read `/tests` or `/solution`.
- The component must work with no network access at all, exactly as it works
  during your local run.