/*
 * Hidden case: filtering semantics on a warehouse SKU list — uncontrolled
 * search, controlled filterText, numeric-value matching, selection surviving
 * a filter, and select-all scoped to the visible rows.
 */
import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { DataTable } from '../DataTable';

interface Crate {
  id: string;
  sku: string;
  qty: number;
  zone: string;
}

const CRATES: Crate[] = [
  { id: 'k1', sku: 'BOLT-6', qty: 120, zone: 'A1' },
  { id: 'k2', sku: 'NUT-M4', qty: 90, zone: 'B2' },
  { id: 'k3', sku: 'BOLT-10', qty: 200, zone: 'A1' },
  { id: 'k4', sku: 'WASH-M4', qty: 45, zone: 'C3' },
  { id: 'k5', sku: 'PIN-T', qty: 60, zone: 'B2' },
  { id: 'k6', sku: 'BOLT-12', qty: 12, zone: 'A3' },
];

const COLUMNS = [
  { key: 'sku', label: 'SKU' },
  { key: 'qty', label: 'Qty', getValue: (r: Crate) => r.qty },
  { key: 'zone', label: 'Zone' },
];

describe('hidden case-filter', () => {
  it('filters across raw values case-insensitively, including numeric ones, and reports every uncontrolled change through onFilterChange', () => {
    const onFilterChange = vi.fn();
    render(
      <DataTable
        data={CRATES}
        columns={COLUMNS}
        getRowId={(r: Crate) => r.id}
        ariaLabel="Crates"
        onFilterChange={onFilterChange}
      />,
    );
    const box = screen.getByRole('searchbox', { name: 'Filter rows' });
    expect(screen.getAllByRole('row').length).toBe(7); // header + 6
    expect(onFilterChange).not.toHaveBeenCalled();

    fireEvent.change(box, { target: { value: 'bolt' } });
    expect(screen.getAllByRole('row').length).toBe(4); // k1 k3 k6 + header
    expect(onFilterChange).toHaveBeenLastCalledWith('bolt');
    expect(screen.queryByRole('checkbox', { name: 'Select row k2' })).toBeNull();

    // numeric raw value is searchable
    fireEvent.change(box, { target: { value: '200' } });
    expect(screen.getAllByRole('row').length).toBe(2); // k3 only

    fireEvent.change(box, { target: { value: '' } });
    expect(screen.getAllByRole('row').length).toBe(7);
  });

  it('filtering hides rows but never drops their selection', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable
        data={CRATES}
        columns={COLUMNS}
        getRowId={(r: Crate) => r.id}
        ariaLabel="Crates"
        selectionMode="multiple"
        onSelectionChange={onSelectionChange}
      />,
    );
    const box = screen.getByRole('searchbox', { name: 'Filter rows' });

    fireEvent.click(screen.getByRole('checkbox', { name: 'Select row k1' }));
    expect(onSelectionChange).toHaveBeenLastCalledWith(['k1']);

    fireEvent.change(box, { target: { value: 'nut' } }); // only k2 visible
    expect(screen.getAllByRole('row').length).toBe(2);
    expect(onSelectionChange).toHaveBeenCalledTimes(1); // filtering is inert

    fireEvent.change(box, { target: { value: '' } });
    expect(
      screen.getByRole('checkbox', { name: 'Select row k1' }).getAttribute('aria-checked'),
    ).toBe('true');

    // select-all operates on the visible (filtered) rows only
    fireEvent.change(box, { target: { value: 'bolt' } });
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select all rows' }));
    expect(onSelectionChange).toHaveBeenLastCalledWith(['k1', 'k3', 'k6']);
    // rows hidden by the filter keep their selection when select-all toggles
    fireEvent.change(box, { target: { value: 'nut' } }); // only k2 visible
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select all rows' }));
    expect(onSelectionChange).toHaveBeenLastCalledWith(['k1', 'k2', 'k3', 'k6']);
  });

  it('controlled filterText drives both the box value and the visible rows', () => {
    const onFilterChange = vi.fn();
    const view = render(
      <DataTable
        data={CRATES}
        columns={COLUMNS}
        getRowId={(r: Crate) => r.id}
        ariaLabel="Crates"
        navigable={false}
        filterText="NUT"
        onFilterChange={onFilterChange}
      />,
    );
    const box = screen.getByRole('searchbox', { name: 'Filter rows' }) as HTMLInputElement;
    expect(box.value).toBe('NUT');
    expect(screen.getAllByRole('row').length).toBe(2); // k2 only

    // typing reports through onFilterChange but does not change state itself
    fireEvent.change(box, { target: { value: 'bolt' } });
    expect(onFilterChange).toHaveBeenLastCalledWith('bolt');
    expect(screen.getAllByRole('row').length).toBe(2); // still controlled 'NUT'

    view.rerender(
      <DataTable
        data={CRATES}
        columns={COLUMNS}
        getRowId={(r: Crate) => r.id}
        ariaLabel="Crates"
        navigable={false}
        filterText="bolt"
        onFilterChange={onFilterChange}
      />,
    );
    expect(screen.getAllByRole('row').length).toBe(4); // k1 k3 k6 + header
  });

  it('defaultFilter seeds the uncontrolled filter at first render', () => {
    render(
      <DataTable
        data={CRATES}
        columns={COLUMNS}
        getRowId={(r: Crate) => r.id}
        ariaLabel="Crates"
        defaultFilter="BOLT"
      />,
    );
    const box = screen.getByRole('searchbox', { name: 'Filter rows' }) as HTMLInputElement;
    expect((box as HTMLInputElement).value).toBe('BOLT');
    expect(screen.getAllByRole('row').length).toBe(4); // k1 k3 k6 + header

    // typing from the seeded value still filters normally
    fireEvent.change(box, { target: { value: 'NUT' } });
    expect(screen.getAllByRole('row').length).toBe(2); // k2 + header
  });

  it('searchable={false} renders no filter box', () => {
    render(
      <DataTable
        data={CRATES}
        columns={COLUMNS}
        getRowId={(r: Crate) => r.id}
        ariaLabel="Crates"
        searchable={false}
      />,
    );
    expect(screen.queryByRole('searchbox')).toBeNull();
    expect(screen.getAllByRole('row').length).toBe(7);
  });
});