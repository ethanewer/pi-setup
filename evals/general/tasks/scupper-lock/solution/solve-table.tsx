/*
 * solve-table.tsx — reference implementation of the scupper-lock deliverable.
 *
 * A generic, accessible React 18 data table with:
 *   - column sorting (aria-sort contract, stable, case-insensitive strings,
 *     numeric values, nulls last in both directions)
 *   - row filtering through an optional search box (uncontrolled or controlled)
 *   - selection in 'none' | 'single' | 'multiple' modes, controlled or
 *     uncontrolled, with a header "select all" checkbox in multiple mode
 *   - grid keyboard navigation (ArrowDown/ArrowUp/Home/End move focus,
 *     Space/Enter toggle selection) behind a `navigable` flag
 *   - custom cell rendering, per-column alignment and class hooks
 *
 * The oracle copies this file verbatim to /app/DataTable.tsx; it is the same
 * implementation an agent is expected to produce from the contract in
 * instruction.md.
 */
import * as React from 'react';
import { useEffect, useMemo, useRef, useState } from 'react';

export type SortDirection = 'asc' | 'desc';

export interface SortState {
  key: string;
  direction: SortDirection;
}

export interface ColumnDef<T> {
  /** stable identifier used for sorting keys and aria-sort */
  key: string;
  /** visible header label */
  label: string;
  /** whether this column participates in sorting (default: table `sortable`) */
  sortable?: boolean;
  /** horizontal alignment of the header label and the cells */
  align?: 'start' | 'center' | 'end';
  /** raw value used for sorting and filtering */
  getValue?: (row: T) => string | number | null | undefined;
  /** custom cell renderer; the returned node is rendered verbatim */
  render?: (row: T, index: number) => React.ReactNode;
  /** extra class on the columnheader */
  headerClassName?: string;
  /** extra class on every cell of this column */
  cellClassName?: string;
}

export interface DataTableProps<T> {
  /** the records to display (unfiltered) */
  data: T[];
  /** column descriptors, in display order */
  columns: ColumnDef<T>[];
  /** stable unique key per record */
  getRowId: (row: T, index: number) => string;
  /** accessible name of the table, default "Data table" */
  ariaLabel?: string;
  /** extra class applied to the root element */
  className?: string;
  /** extra class applied to a rendered row */
  getRowClassName?: (row: T, index: number) => string | undefined;
  /** 'none' | 'single' | 'multiple'; default 'none' */
  selectionMode?: 'none' | 'single' | 'multiple';
  /** controlled selection (array of row ids) */
  selectedIds?: string[];
  /** initial selection when selection is uncontrolled */
  defaultSelectedIds?: string[];
  /** called whenever the selection changes (ids in `data` order) */
  onSelectionChange?: (ids: string[]) => void;
  /** default for column sortability; default true */
  sortable?: boolean;
  /** initial sort state */
  defaultSort?: SortState;
  /** called with the new sort state after a header click */
  onSortChange?: (sort: SortState) => void;
  /** whether the filter search box is rendered; default true */
  searchable?: boolean;
  /** initial filter text when the filter is uncontrolled */
  defaultFilter?: string;
  /** controlled filter text */
  filterText?: string;
  /** called when the filter text changes */
  onFilterChange?: (text: string) => void;
  /** whether grid keyboard navigation is enabled; default true */
  navigable?: boolean;
}

/** Compare two present values: numbers numerically, strings
 *  case-insensitively in code-unit order. Callers handle null/undefined. */
function compareValues(a: unknown, b: unknown): number {
  if (typeof a === 'number' && typeof b === 'number') return a - b;
  const sa = String(a).toLowerCase();
  const sb = String(b).toLowerCase();
  if (sa < sb) return -1;
  if (sa > sb) return 1;
  return 0;
}

function isMissing(v: unknown): boolean {
  return v === null || v === undefined;
}

/** Stable sort: equal keys keep their original relative order, and rows
 *  whose sort value is null/undefined always sort last in BOTH directions. */
function stableSort<T>(rows: T[], keyFn: (r: T) => unknown, dir: SortDirection): T[] {
  const withIdx = rows.map((row, index) => ({ row, index }));
  const mul = dir === 'asc' ? 1 : -1;
  withIdx.sort((a, b) => {
    const av = keyFn(a.row);
    const bv = keyFn(b.row);
    const aMiss = isMissing(av);
    const bMiss = isMissing(bv);
    if (aMiss || bMiss) {
      if (aMiss && bMiss) return a.index - b.index;
      return aMiss ? 1 : -1;
    }
    const cmp = compareValues(av, bv);
    if (cmp !== 0) return cmp * mul;
    return a.index - b.index;
  });
  return withIdx.map((x) => x.row);
}

function rawValue<T>(col: ColumnDef<T>, row: T): unknown {
  if (col.getValue) return col.getValue(row);
  return (row as Record<string, unknown>)[col.key];
}

export function DataTable<T>(props: DataTableProps<T>): React.JSX.Element {
  const {
    data,
    columns,
    getRowId,
    ariaLabel = 'Data table',
    className,
    getRowClassName,
    selectionMode = 'none',
    selectedIds,
    defaultSelectedIds,
    onSelectionChange,
    sortable = true,
    defaultSort,
    onSortChange,
    searchable = true,
    defaultFilter,
    filterText,
    onFilterChange,
    navigable = true,
  } = props;

  const [sort, setSort] = useState<SortState | null>(defaultSort ?? null);
  const [internalFilter, setInternalFilter] = useState(defaultFilter ?? '');
  const [uncontrolledSelection, setUncontrolledSelection] = useState<string[]>(
    defaultSelectedIds ?? [],
  );
  const [activeRowId, setActiveRowId] = useState<string | null>(null);
  const rowEls = useRef<Array<HTMLDivElement | null>>([]);

  const selection: Set<string> = useMemo(() => {
    const src = selectedIds !== undefined ? selectedIds : uncontrolledSelection;
    return new Set(src);
  }, [selectedIds, uncontrolledSelection]);

  const query = filterText !== undefined ? filterText : internalFilter;

  const filtered = useMemo(() => {
    if (!query) return data;
    const q = query.toLowerCase();
    return data.filter((row) =>
      columns.some((col) => {
        const v = rawValue(col, row);
        if (v === null || v === undefined) return false;
        return String(v).toLowerCase().includes(q);
      }),
    );
  }, [data, columns, query]);

  const sorted = useMemo(() => {
    if (!sort) return filtered;
    const col = columns.find((c) => c.key === sort.key);
    if (!col) return filtered;
    return stableSort(filtered, (row) => rawValue(col, row), sort.direction);
  }, [filtered, columns, sort]);

  const ids: string[] = useMemo(
    () => sorted.map((row, index) => getRowId(row, index)),
    [sorted, getRowId],
  );

  // keep the keyboard cursor on a row that is still visible
  useEffect(() => {
    if (activeRowId !== null && !ids.includes(activeRowId)) {
      setActiveRowId(ids.length > 0 ? ids[0] : null);
    }
  }, [ids, activeRowId]);

  // ------------------------------------------------------------------ helpers
  const selectedInDataOrder = (sel: Set<string>): string[] =>
    data.map((row, i) => getRowId(row, i)).filter((id) => sel.has(id));

  const commitSelection = (next: Set<string>) => {
    if (selectedIds === undefined) {
      setUncontrolledSelection(selectedInDataOrder(next));
    }
    onSelectionChange?.(selectedInDataOrder(next));
  };

  const toggleOne = (rowId: string) => {
    const next = new Set(selection);
    if (next.has(rowId)) next.delete(rowId);
    else next.add(rowId);
    commitSelection(next);
  };

  const isSortableCol = (col: ColumnDef<T>) => col.sortable ?? sortable;

  const handleHeaderClick = (col: ColumnDef<T>) => {
    if (!isSortableCol(col)) return;
    const next =
      sort && sort.key === col.key
        ? { key: col.key, direction: (sort.direction === 'asc' ? 'desc' : 'asc') as SortDirection }
        : { key: col.key, direction: 'asc' as SortDirection };
    setSort(next);
    onSortChange?.(next);
  };

  const handleFilterChange = (value: string) => {
    if (filterText !== undefined) {
      onFilterChange?.(value);
    } else {
      setInternalFilter(value);
      onFilterChange?.(value);
    }
  };

  const allVisibleSelected = ids.length > 0 && ids.every((id) => selection.has(id));
  const someVisibleSelected = ids.some((id) => selection.has(id));

  const handleSelectAll = () => {
    if (selectionMode !== 'multiple') return;
    const next = new Set(selection);
    if (allVisibleSelected) {
      for (const id of ids) next.delete(id);
    } else {
      for (const id of ids) next.add(id);
    }
    commitSelection(next);
  };

  const moveFocusTo = (target: number) => {
    const el = rowEls.current[target];
    if (el) el.focus();
  };

  const toggleRowById = (rowId: string) => {
    if (selectionMode === 'none') return;
    if (selectionMode === 'single') {
      if (selection.has(rowId)) return;
      commitSelection(new Set([rowId]));
    } else {
      toggleOne(rowId);
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>, index: number) => {
    if (!navigable) return;
    const last = ids.length - 1;
    switch (e.key) {
      case 'ArrowDown':
        e.preventDefault();
        if (index < last) moveFocusTo(index + 1);
        break;
      case 'ArrowUp':
        e.preventDefault();
        if (index > 0) moveFocusTo(index - 1);
        break;
      case 'Home':
        e.preventDefault();
        if (ids.length > 0) moveFocusTo(0);
        break;
      case 'End':
        e.preventDefault();
        if (ids.length > 0) moveFocusTo(last);
        break;
      case ' ':
      case 'Enter':
        e.preventDefault();
        toggleRowById(ids[index]);
        break;
      default:
        break;
    }
  };

  const handleRowClick = (rowId: string) => {
    if (selectionMode === 'single' && !selection.has(rowId)) {
      commitSelection(new Set([rowId]));
    }
  };

  // ---------------------------------------------------------------- render
  const gridRole = navigable ? 'grid' : 'table';
  const cellRole = navigable ? 'gridcell' : 'cell';
  const activeIndex = activeRowId === null ? 0 : ids.indexOf(activeRowId);

  return (
    <div className={className} role={gridRole} aria-label={ariaLabel}>
      {searchable && (
        <div role="search">
          <input
            type="search"
            aria-label="Filter rows"
            value={filterText !== undefined ? filterText : internalFilter}
            onChange={(e) => handleFilterChange(e.target.value)}
          />
        </div>
      )}
      <div role="rowgroup">
        <div role="row">
          {selectionMode === 'multiple' && (
            <div role="columnheader" className="dt-select-head">
              <input
                type="checkbox"
                aria-label="Select all rows"
                checked={allVisibleSelected}
                aria-checked={
                  allVisibleSelected ? 'true' : someVisibleSelected ? 'mixed' : 'false'
                }
                onChange={handleSelectAll}
              />
            </div>
          )}
          {columns.map((col) => {
            const colSortable = isSortableCol(col);
            const active = sort !== null && sort.key === col.key;
            return (
              <div
                key={col.key}
                role="columnheader"
                aria-sort={
                  colSortable
                    ? active
                      ? sort.direction === 'asc'
                        ? 'ascending'
                        : 'descending'
                      : 'none'
                    : undefined
                }
                className={col.headerClassName}
                style={col.align ? { textAlign: col.align } : undefined}
              >
                {colSortable ? (
                  <button type="button" onClick={() => handleHeaderClick(col)}>
                    {col.label}
                  </button>
                ) : (
                  <span>{col.label}</span>
                )}
              </div>
            );
          })}
        </div>
      </div>
      <div role="rowgroup">
        {sorted.map((row, index) => {
          const rowId = ids[index];
          const isActive =
            navigable && (activeRowId === null ? index === 0 : rowId === activeRowId);
          return (
            <div
              key={rowId}
              role="row"
              ref={(el) => {
                rowEls.current[index] = el;
              }}
              tabIndex={navigable ? (isActive ? 0 : -1) : undefined}
              aria-selected={
                selectionMode !== 'none' ? (selection.has(rowId) ? 'true' : 'false') : undefined
              }
              className={getRowClassName ? getRowClassName(row, index) : undefined}
              onClick={() => handleRowClick(rowId)}
              onFocus={() => setActiveRowId(rowId)}
              onKeyDown={(e) => handleKeyDown(e, index)}
            >
              {selectionMode === 'multiple' && (
                <div role={cellRole} className="dt-select-cell">
                  <input
                    type="checkbox"
                    aria-label={`Select row ${rowId}`}
                    checked={selection.has(rowId)}
                    aria-checked={selection.has(rowId) ? 'true' : 'false'}
                    onChange={() => toggleOne(rowId)}
                  />
                </div>
              )}
              {columns.map((col) => {
                const val = rawValue(col, row);
                return (
                  <div
                    key={col.key}
                    role={cellRole}
                    className={col.cellClassName}
                    style={col.align ? { textAlign: col.align } : undefined}
                  >
                    {col.render ? col.render(row, index) : String(val ?? '')}
                  </div>
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default DataTable;