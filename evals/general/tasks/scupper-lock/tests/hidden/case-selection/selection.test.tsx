/*
 * Hidden case: selection semantics on an appliance catalogue — uncontrolled
 * and controlled multiple selection, select-all with mixed state, payload
 * ordering in `data` order, and single-mode keyboard selection.
 */
import { describe, expect, it, vi } from 'vitest';
import { useRef, useState } from 'react';
import { act, fireEvent, render, screen } from '@testing-library/react';
import { DataTable } from '../DataTable';

interface Oven {
  id: string;
  model: string;
  temp: number;
}

const OVENS: Oven[] = [
  { id: 'o1', model: 'Ember 900', temp: 200 },
  { id: 'o2', model: 'Flare Mini', temp: 160 },
  { id: 'o3', model: 'Sinter DX', temp: 240 },
  { id: 'o4', model: 'Kiln 3', temp: 180 },
];

const COLUMNS = [
  { key: 'model', label: 'Model' },
  { key: 'temp', label: 'Temp', getValue: (r: Oven) => r.temp, align: 'end' as const },
];

function ControlledSelect({ onSelectionChange }: { onSelectionChange: (ids: string[]) => void }) {
  const [selectedIds, setSelectedIds] = useState<string[]>(['o2']);
  const spy = useRef(
    (ids: string[]) => {
      onSelectionChange(ids);
      setSelectedIds(ids);
    },
  ).current;
  return (
    <DataTable
      data={OVENS}
      columns={COLUMNS}
      getRowId={(r: Oven) => r.id}
      searchable={false}
      navigable={false}
      ariaLabel="Ovens"
      selectionMode="multiple"
      selectedIds={selectedIds}
      onSelectionChange={spy}
    />
  );
}

describe('hidden case-selection', () => {
  it('uncontrolled multiple: row toggles, select-all and mixed state', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable
        data={OVENS}
        columns={COLUMNS}
        getRowId={(r: Oven) => r.id}
        searchable={false}
        navigable={false}
        ariaLabel="Ovens"
        selectionMode="multiple"
        onSelectionChange={onSelectionChange}
      />,
    );
    const all = screen.getByRole('checkbox', { name: 'Select all rows' });
    expect(all.getAttribute('aria-checked')).toBe('false');

    const o1 = screen.getByRole('checkbox', { name: 'Select row o1' });
    fireEvent.click(o1);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o1']);
    expect(o1.getAttribute('aria-checked')).toBe('true');
    expect(all.getAttribute('aria-checked')).toBe('mixed');

    fireEvent.click(screen.getByRole('checkbox', { name: 'Select row o3' }));
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o1', 'o3']);

    // deselect one
    fireEvent.click(o1);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o3']);

    // select all then clear
    fireEvent.click(all);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o1', 'o2', 'o3', 'o4']);
    fireEvent.click(all);
    expect(onSelectionChange).toHaveBeenLastCalledWith([]);
  });

  it('controlled selection: props drive the checkboxes, events report data order', () => {
    const onSelectionChange = vi.fn();
    render(<ControlledSelect onSelectionChange={onSelectionChange} />);
    const o2 = screen.getByRole('checkbox', { name: 'Select row o2' });
    expect(o2.getAttribute('aria-checked')).toBe('true');

    const o3 = screen.getByRole('checkbox', { name: 'Select row o3' });
    fireEvent.click(o3);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o2', 'o3']);
    expect(o3.getAttribute('aria-checked')).toBe('true');

    // select-all reflects the visible rows
    const all = screen.getByRole('checkbox', { name: 'Select all rows' });
    expect(all.getAttribute('aria-checked')).toBe('mixed');
    fireEvent.click(all);
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o1', 'o2', 'o3', 'o4']);
  });

  it('single mode: row click moves aria-selected and clicking the same row is inert', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable
        data={OVENS}
        columns={COLUMNS}
        getRowId={(r: Oven) => r.id}
        searchable={false}
        navigable={false}
        ariaLabel="Ovens"
        selectionMode="single"
        defaultSelectedIds={['o4']}
        onSelectionChange={onSelectionChange}
      />,
    );
    let rows = screen.getAllByRole('row');
    expect(rows[1].getAttribute('aria-selected')).toBe('false'); // o1
    expect(rows[4].getAttribute('aria-selected')).toBe('true'); // o4

    fireEvent.click(rows[2]); // o2
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o2']);
    expect(rows[2].getAttribute('aria-selected')).toBe('true');
    expect(rows[4].getAttribute('aria-selected')).toBe('false');

    fireEvent.click(rows[2]);
    expect(onSelectionChange).toHaveBeenCalledTimes(1);
  });

  it('single mode keyboard: arrows move the grid cursor, Enter selects', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable
        data={OVENS}
        columns={COLUMNS}
        getRowId={(r: Oven) => r.id}
        searchable={false}
        ariaLabel="Ovens"
        selectionMode="single"
        onSelectionChange={onSelectionChange}
      />,
    );
    const rows = screen.getAllByRole('row');
    act(() => { (rows[1] as HTMLElement).focus(); });
    fireEvent.keyDown(rows[1], { key: 'ArrowDown' });
    expect(document.activeElement).toBe(rows[2]);

    fireEvent.keyDown(rows[2], { key: 'Enter' });
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o2']);
    expect(rows[2].getAttribute('aria-selected')).toBe('true');
  });

  it('selection payloads stay in data order even while the rows are sorted into a different display order', () => {
    const onSelectionChange = vi.fn();
    render(
      <DataTable
        data={OVENS}
        columns={COLUMNS}
        getRowId={(r: Oven) => r.id}
        searchable={false}
        navigable={false}
        ariaLabel="Ovens"
        selectionMode="multiple"
        onSelectionChange={onSelectionChange}
      />,
    );
    // sort ascending by temp -> display o2(160), o4(180), o1(200), o3(240)
    fireEvent.click(screen.getByRole('button', { name: 'Temp' }));
    const display = screen.getAllByRole('row').slice(1).map((r) => r.textContent);
    expect(display[0]).toContain('Flare Mini'); // o2 first when sorted

    // select the row displayed second (o4) first, then the row displayed fourth (o3)
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select row o4' }));
    fireEvent.click(screen.getByRole('checkbox', { name: 'Select row o3' }));
    // payload ids come from data order o1 o2 o3 o4, never from display order
    expect(onSelectionChange).toHaveBeenLastCalledWith(['o3', 'o4']);
    expect(onSelectionChange).toHaveBeenNthCalledWith(1, ['o4']);
  });
});