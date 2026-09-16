# DataTable — API reference

`DataTable` is a generic, accessible React 18 data table component. It is the
nominal export of this module, together with the types `DataTableProps`,
`ColumnDef`, `SortState` and `SortDirection`.

## Exports

- `DataTable` — the component. `export default` is identical.
- `DataTableProps<T>` — the prop type, generic over the row type `T`.
- `ColumnDef<T>` — a column descriptor.
- `SortState` — `{ key: string; direction: SortDirection }`.
- `SortDirection` — `'asc' | 'desc'`.

## Props (`DataTableProps<T>`)

| Prop | Type | Default | Description |
| --- | --- | --- | --- |
| `data` | `T[]` | — | Records to display. |
| `columns` | `ColumnDef<T>[]` | — | Column descriptors in display order. |
| `getRowId` | `(row: T, index: number) => string` | — | Stable unique id per record; used for keys, `aria-label`s and selection. |
| `ariaLabel` | `string` | `"Data table"` | Accessible name of the grid/table. |
| `className` | `string` | — | Extra class on the root element. |
| `getRowClassName` | `(row: T, index: number) => string \| undefined` | — | Extra class per rendered row. |
| `selectionMode` | `'none' \| 'single' \| 'multiple'` | `'none'` | Selection policy. |
| `selectedIds` | `string[]` | — | Controlled selection (ids returned by `getRowId`). |
| `defaultSelectedIds` | `string[]` | — | Initial selection when uncontrolled. |
| `onSelectionChange` | `(ids: string[]) => void` | — | Fired with the new selection, ids ordered by position in `data`. |
| `sortable` | `boolean` | `true` | Default sortability for columns without their own `sortable`. |
| `defaultSort` | `SortState` | — | Initial sort state. |
| `onSortChange` | `(sort: SortState) => void` | — | Fired with the new sort state after a header click. |
| `searchable` | `boolean` | `true` | Renders the filter search box. |
| `defaultFilter` | `string` | — | Initial filter text when uncontrolled. |
| `filterText` | `string` | — | Controlled filter text (takes precedence; typing reports via `onFilterChange`, state is not changed). |
| `onFilterChange` | `(text: string) => void` | — | Fired when the filter text changes. |
| `navigable` | `boolean` | `true` | Enables grid keyboard navigation. |

## ColumnDef

| Field Type | Description |
| --- | --- |
| `key: string` | Stable column identifier, also the sort/aria-sort identity. |
| `label: string` | Header label. |
| `sortable?: boolean` | Defaults to the table `sortable` prop. |
| `align?: 'start' \| 'center' \| 'end'` | `textAlign` of the header and cells. |
| `getValue?` | `(row: T) => string \| number \| null \| undefined`; raw value used for sorting and filtering (falls back to `row[key]`). |
| `render?` | `(row: T, index: number) => React.ReactNode`; custom cell content. |
| `headerClassName?: string` | Extra class on the columnheader. |
| `cellClassName?: string` | Extra class on every cell of this column. |

## Behavior

- **Sorting**: clicking a sortable header toggles `asc` → `desc` → `asc`;
  clicking a new column re-sorts ascending. Sortable headers carry
  `aria-sort="ascending|descending|none"`; non-sortable headers expose no
  `aria-sort` and no button. Comparison: numbers numerically, strings
  case-insensitively (code-unit order), `null`/`undefined` last in both
  directions, equal keys stable.
- **Filtering**: a search box (`aria-label="Filter rows"`, `role="searchbox"`)
  filters rows by case-insensitive substring across each column's raw values
  (`getValue` or `row[key]`). Filtering never changes the selection.
- **Selection**: in `multiple` mode each row has a checkbox
  (`aria-label="Select row <id>"`) and the header shows a select-all checkbox
  (`aria-label="Select all rows"`) with `aria-checked="mixed"` for partial
  selection, scoped to visible rows. In `single` mode clicking a row selects
  it; clicking the selected row is a no-op. `aria-selected` is set on every
  row whenever `selectionMode !== 'none'`.
- **Keyboard**: when `navigable`, one row carries `tabindex="0"`;
  ArrowUp/ArrowDown/Home/End move the grid cursor, Space/Enter toggle the
  focused row's selection.
- **Roles**: the root is `role="grid"` when `navigable` (cells `role="gridcell"`)
  and `role="table"` otherwise (cells `role="cell"`). A single header row
  (`role="row"` of `role="columnheader"`) precedes the data rows.

This implementation keeps internal UI state with React hooks and defers to
props whenever a controlled value (`selectedIds`, `filterText`) is supplied.