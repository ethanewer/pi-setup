/*
 * Hidden case: rendering hooks and table mode on a team roster — navigable
 * off (plain table role), custom render, per-column class hooks, alignment,
 * getRowClassName, an initial defaultSort, and non-sortable columns.
 */
import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen, within } from '@testing-library/react';
import { DataTable, ColumnDef } from '../DataTable';

interface Member {
  id: string;
  name: string;
  role: string;
  score: number | null;
  tag: string;
}

const MEMBERS: Member[] = [
  { id: 'm1', name: 'ada', role: 'lead', score: 92, tag: 'core' },
  { id: 'm2', name: 'bob', role: 'dev', score: 84, tag: 'edge' },
  { id: 'm3', name: 'cyn', role: 'dev', score: null, tag: 'core' },
  { id: 'm4', name: 'dax', role: 'qa', score: 91, tag: 'edge' },
];

const COLUMNS: ColumnDef<Member>[] = [
  { key: 'name', label: 'Name', render: (m) => <strong>{m.name}</strong> },
  { key: 'role', label: 'Role', sortable: false, align: 'end' },
  { key: 'score', label: 'Score', getValue: (m) => m.score, cellClassName: 'score-cell' },
  { key: 'tag', label: 'Tag', headerClassName: 'tag-head' },
];

function setup(extra: Record<string, unknown> = {}) {
  const onSelectionChange = vi.fn();
  render(
    <DataTable
      data={MEMBERS}
      columns={COLUMNS}
      getRowId={(m: Member) => m.id}
      searchable={false}
      ariaLabel="Team"
      navigable={false}
      className="panel"
      getRowClassName={(m: Member) => (m.score === null ? 'pending' : 'rated')}
      onSelectionChange={onSelectionChange}
      {...(extra as object)}
    />,
  );
  return { onSelectionChange };
}

describe('hidden case-styles', () => {
  it('navigable={false} renders a table with cells, not a grid', () => {
    setup();
    expect(screen.queryByRole('grid')).toBeNull();
    expect(screen.getByRole('table', { name: 'Team' })).toBeTruthy();
    expect(screen.getAllByRole('cell').length).toBe(16); // 4 members x 4 columns
    const rows = screen.getAllByRole('row');
    expect(rows.length).toBe(5);
    // rows are not keyboard-focusable in table mode
    expect(rows[1].hasAttribute('tabindex')).toBe(false);
    // selectionMode defaults to none -> no aria-selected at all
    expect(rows[1].hasAttribute('aria-selected')).toBe(false);
  });

  it('applies className, getRowClassName and per-cell class hooks', () => {
    setup();
    expect(screen.getByRole('table').classList.contains('panel')).toBe(true);
    const rows = screen.getAllByRole('row');
    expect(rows[1].classList.contains('rated')).toBe(true);
    expect(rows[3].classList.contains('pending')).toBe(true); // m3 has null score
    expect(rows[2].classList.contains('rated')).toBe(true);
    // cell class hook
    expect(screen.getByRole('cell', { name: '92' }).classList.contains('score-cell')).toBe(true);
    // header class hook
    expect(
      screen.getByRole('columnheader', { name: 'Tag' }).classList.contains('tag-head'),
    ).toBe(true);
  });

  it('renders custom cell content and alignment from the column defs', () => {
    setup();
    const firstRow = screen.getAllByRole('row')[1];
    const nameCell = within(firstRow).getByText('ada');
    expect(nameCell.tagName).toBe('STRONG');
    // align 'end' applies to every header/cell with that column def
    const roleHeader = screen.getByRole('columnheader', { name: 'Role' });
    expect(roleHeader.style.textAlign).toBe('end');
  });

  it('applies initialSort from defaultSort and keeps nulls last', () => {
    setup({ defaultSort: { key: 'score', direction: 'asc' } });
    expect(
      screen.getByRole('columnheader', { name: 'Score' }).getAttribute('aria-sort'),
    ).toBe('ascending');
    const titles = screen
      .getAllByRole('row')
      .slice(1)
      .map((r) => r.textContent);
    expect(titles[0]).toContain('bob'); // 84
    expect(titles[1]).toContain('dax'); // 91
    expect(titles[2]).toContain('ada'); // 92
    expect(titles[3]).toContain('cyn'); // null last
  });

  it('non-sortable columns carry no aria-sort and never reorder', () => {
    const { onSelectionChange } = setup({
      defaultSort: { key: 'name', direction: 'asc' },
      selectionMode: 'single',
      defaultSelectedIds: ['m4'],
    });
    const roleHeader = screen.getByRole('columnheader', { name: 'Role' });
    expect(roleHeader.getAttribute('aria-sort')).toBeNull();
    expect(screen.queryByRole('button', { name: 'Role' })).toBeNull();
    expect(
      screen.getByRole('columnheader', { name: 'Name' }).getAttribute('aria-sort'),
    ).toBe('ascending');

    const before = screen
      .getAllByRole('row')
      .slice(1)
      .map((r) => r.textContent);
    fireEvent.click(roleHeader); // clicking a non-sortable header is inert
    const after = screen
      .getAllByRole('row')
      .slice(1)
      .map((r) => r.textContent);
    expect(after).toEqual(before);
    expect(onSelectionChange).not.toHaveBeenCalled();
  });

  it('table-level sortable={false} disables every column', () => {
    const onSortChange = vi.fn();
    render(
      <DataTable
        data={MEMBERS}
        columns={COLUMNS}
        getRowId={(m: Member) => m.id}
        searchable={false}
        navigable={false}
        ariaLabel="Team"
        sortable={false}
        onSortChange={onSortChange}
      />,
    );
    expect(screen.queryByRole('button')).toBeNull();
    const headers = screen.getAllByRole('columnheader');
    expect(headers.every((h) => h.getAttribute('aria-sort') === null)).toBe(true);
    const before = headers.map((r) => r.textContent);
    fireEvent.click(screen.getByRole('columnheader', { name: 'Name' }));
    expect(onSortChange).not.toHaveBeenCalled();
    expect(headers.map((r) => r.textContent)).toEqual(before);
  });

  it('defaults the accessible name to "Data table" when ariaLabel is omitted', () => {
    render(
      <DataTable
        data={MEMBERS}
        columns={COLUMNS}
        getRowId={(m: Member) => m.id}
        searchable={false}
        navigable={false}
      />,
    );
    expect(screen.getByRole('table', { name: 'Data table' })).toBeTruthy();
  });
});