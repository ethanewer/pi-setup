/*
 * visible.test.tsx — the visible test suite for the scupper-lock deliverable.
 *
 * The agent can run these locally while building /app/DataTable.tsx:
 *
 *     cd /app && npx vitest run
 *     cd /app && npm run typecheck
 *
 * The verifier runs this same suite plus a set of hidden fixtures (different
 * datasets, more prop combinations) and strict type-checks two hidden consumer
 * files against the exported prop types.
 */
import { describe, expect, it, vi } from 'vitest';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { DataTable, DataTableProps } from '../DataTable';

interface Person {
  id: string;
  name: string;
  dept: string;
  level: number;
}

const PEOPLE: Person[] = [
  { id: 'p1', name: 'zoe', dept: 'eng', level: 3 },
  { id: 'p2', name: 'alex', dept: 'ops', level: 5 },
  { id: 'p3', name: 'kai', dept: 'eng', level: 1 },
  { id: 'p4', name: 'marin', dept: 'ops', level: 2 },
];

const COLUMNS = [
  { key: 'name', label: 'Name' },
  { key: 'dept', label: 'Dept' },
  { key: 'level', label: 'Level', getValue: (r: Person) => r.level },
];

function baseProps(overrides: Partial<DataTableProps<Person>> = {}): DataTableProps<Person> {
  return {
    data: PEOPLE,
    columns: COLUMNS,
    getRowId: (r) => r.id,
    ariaLabel: 'Staff',
    searchable: false,
    ...overrides,
  };
}

describe('scupper-lock visible fixtures', () => {
  it('renders a grid with one header row and one row per record', () => {
    render(<DataTable {...baseProps()} />);
    const grid = screen.getByRole('grid', { name: 'Staff' });
    expect(grid).toBeTruthy();
    // header row + 4 data rows
    expect(screen.getAllByRole('row').length).toBe(5);
    // every column exposes a sortable header button
    expect(screen.getByRole('button', { name: 'Name' })).toBeTruthy();
    expect(screen.getByRole('button', { name: 'Level' })).toBeTruthy();
    // unsorted sortable headers carry aria-sort="none"
    expect(screen.getByRole('columnheader', { name: 'Name' }).getAttribute('aria-sort')).toBe(
      'none',
    );
    // initial row order follows the data array
    const rows = screen.getAllByRole('row');
    expect(rows[1].textContent).toContain('zoe');
    expect(rows[4].textContent).toContain('marin');
  });

  it('sorts on header click with aria-sort and onSortChange (asc -> desc -> asc)', () => {
    const onSortChange = vi.fn();
    render(<DataTable {...baseProps({ onSortChange })} />);
    const nameBtn = screen.getByRole('button', { name: 'Name' });

    fireEvent.click(nameBtn);
    let rows = screen.getAllByRole('row');
    expect(rows[1].textContent).toContain('alex');
    expect(rows[4].textContent).toContain('zoe');
    expect(onSortChange).toHaveBeenLastCalledWith({ key: 'name', direction: 'asc' });
    expect(screen.getByRole('columnheader', { name: 'Name' }).getAttribute('aria-sort')).toBe(
      'ascending',
    );

    fireEvent.click(nameBtn);
    rows = screen.getAllByRole('row');
    expect(rows[1].textContent).toContain('zoe');
    expect(onSortChange).toHaveBeenLastCalledWith({ key: 'name', direction: 'desc' });
    expect(screen.getByRole('columnheader', { name: 'Name' }).getAttribute('aria-sort')).toBe(
      'descending',
    );

    fireEvent.click(nameBtn);
    rows = screen.getAllByRole('row');
    expect(rows[1].textContent).toContain('alex');
    expect(onSortChange).toHaveBeenLastCalledWith({ key: 'name', direction: 'asc' });
  });

  it('sorts numbers numerically when the column defines getValue', () => {
    render(<DataTable {...baseProps()} />);
    fireEvent.click(screen.getByRole('button', { name: 'Level' }));
    const rows = screen.getAllByRole('row');
    // 1 -> 2 -> 3 -> 5
    expect(rows[1].textContent).toContain('kai');
    expect(rows[2].textContent).toContain('marin');
    expect(rows[3].textContent).toContain('zoe');
    expect(rows[4].textContent).toContain('alex');
  });

  it('supports uncontrolled multiple selection with select-all and mixed state', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable {...baseProps({ selectionMode: 'multiple', onSelectionChange })} />,
    );
    const all = screen.getByRole('checkbox', { name: 'Select all rows' });
    expect(all.getAttribute('aria-checked')).toBe('false');

    const p1 = screen.getByRole('checkbox', { name: 'Select row p1' });
    fireEvent.click(p1);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['p1']);
    expect(p1.getAttribute('aria-checked')).toBe('true');
    expect(all.getAttribute('aria-checked')).toBe('mixed');

    fireEvent.click(all);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['p1', 'p2', 'p3', 'p4']);
    expect(all.getAttribute('aria-checked')).toBe('true');

    fireEvent.click(all);
    expect(onSelectionChange).toHaveBeenLastCalledWith([]);
    expect(all.getAttribute('aria-checked')).toBe('false');
  });

  it('supports single selection by row click with aria-selected', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable
        {...baseProps({ selectionMode: 'single', defaultSelectedIds: ['p2'], onSelectionChange })}
      />,
    );
    const rows = screen.getAllByRole('row');
    expect(rows[1].getAttribute('aria-selected')).toBe('false');
    expect(rows[2].getAttribute('aria-selected')).toBe('true');

    fireEvent.click(rows[1]);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['p1']);
    expect(rows[1].getAttribute('aria-selected')).toBe('true');
    expect(rows[2].getAttribute('aria-selected')).toBe('false');

    // clicking the already-selected row is a no-op
    fireEvent.click(rows[1]);
    expect(onSelectionChange).toHaveBeenCalledTimes(1);
  });

  it('filters rows from the search box (case-insensitive substring)', () => {
    render(<DataTable {...baseProps({ searchable: true })} />);
    const search = screen.getByRole('searchbox', { name: 'Filter rows' });

    fireEvent.change(search, { target: { value: 'kai' } });
    expect(screen.getAllByRole('row').length).toBe(2); // header + kai

    fireEvent.change(search, { target: { value: 'OPS' } });
    expect(screen.getAllByRole('row').length).toBe(3); // header + alex + marin

    fireEvent.change(search, { target: { value: '' } });
    expect(screen.getAllByRole('row').length).toBe(5);
  });

  it('navigates rows with the keyboard and toggles selection on Space', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable {...baseProps({ selectionMode: 'multiple', onSelectionChange })} />,
    );
    const rows = screen.getAllByRole('row');
    act(() => { (rows[1] as HTMLElement).focus(); });
    expect(document.activeElement).toBe(rows[1]);

    fireEvent.keyDown(rows[1], { key: 'ArrowDown' });
    expect(document.activeElement).toBe(rows[2]);

    fireEvent.keyDown(rows[2], { key: ' ' });
    expect(onSelectionChange).toHaveBeenLastCalledWith(['p2']);

    fireEvent.keyDown(rows[2], { key: 'End' });
    expect(document.activeElement).toBe(rows[4]);

    fireEvent.keyDown(rows[4], { key: 'Home' });
    expect(document.activeElement).toBe(rows[1]);
  });
});