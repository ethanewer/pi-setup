/*
 * Hidden case: sorting semantics on a library catalogue.
 *
 * Exercises the sort contract beyond the visible fixture: mixed-case and
 * numeric columns, null values sorted last in both directions, stable ties,
 * non-sortable columns carrying no aria-sort, and sort state pushed through
 * onSortChange.
 */
import { describe, expect, it, vi } from 'vitest';
import { fireEvent, render, screen } from '@testing-library/react';
import { DataTable } from '../DataTable';

interface Book {
  id: string;
  title: string;
  author: string;
  pages: number | null;
}

const BOOKS: Book[] = [
  { id: 'b1', title: 'Moby-Dick', author: 'melville', pages: 635 },
  { id: 'b2', title: 'The Hobbit', author: 'Tolkien', pages: 310 },
  { id: 'b3', title: 'Dune', author: 'herbert', pages: 412 },
  { id: 'b4', title: 'The Stranger', author: 'camus', pages: 123 },
  { id: 'b5', title: 'Dune Messiah', author: 'herbert', pages: 256 },
  { id: 'b6', title: 'The Old Man and the Sea', author: 'HEMINGWAY', pages: null },
];

const COLUMNS = [
  { key: 'id', label: 'ID', sortable: false },
  { key: 'title', label: 'Title' },
  { key: 'author', label: 'Author' },
  { key: 'pages', label: 'Pages', getValue: (r: Book) => r.pages },
];

function setup(extra: Record<string, unknown> = {}) {
  const onSortChange = vi.fn();
  const utils = render(
    <DataTable
      data={BOOKS}
      columns={COLUMNS}
      getRowId={(r) => r.id}
      searchable={false}
      ariaLabel="Library"
      onSortChange={onSortChange}
      {...(extra as object)}
    />,
  );
  return { onSortChange, ...utils };
}

const rowTitles = () => screen.getAllByRole('row').slice(1).map((r) => r.textContent);

describe('hidden case-sort', () => {
  it('sorts strings case-insensitively, asc then desc then asc on repeat', () => {
    const { onSortChange } = setup();
    const authorBtn = screen.getByRole('button', { name: 'Author' });

    fireEvent.click(authorBtn);
    // camus, HEMINGWAY(hemingway), herbert, herbert, melville, tolkien
    expect(rowTitles()).toEqual([
      expect.stringContaining('The Stranger'),
      expect.stringContaining('The Old Man and the Sea'),
      expect.stringContaining('Dune'),
      expect.stringContaining('Dune Messiah'),
      expect.stringContaining('Moby-Dick'),
      expect.stringContaining('The Hobbit'),
    ]);
    expect(onSortChange).toHaveBeenLastCalledWith({ key: 'author', direction: 'asc' });
    expect(screen.getByRole('columnheader', { name: 'Author' }).getAttribute('aria-sort')).toBe(
      'ascending',
    );
    // other sortable headers stay at aria-sort="none"
    expect(screen.getByRole('columnheader', { name: 'Title' }).getAttribute('aria-sort')).toBe(
      'none',
    );

    fireEvent.click(authorBtn);
    expect(rowTitles()).toEqual([
      expect.stringContaining('The Hobbit'),
      expect.stringContaining('Moby-Dick'),
      expect.stringContaining('Dune'),
      expect.stringContaining('Dune Messiah'),
      expect.stringContaining('The Old Man and the Sea'),
      expect.stringContaining('The Stranger'),
    ]);
    expect(
      screen.getByRole('columnheader', { name: 'Author' }).getAttribute('aria-sort'),
    ).toBe('descending');

    fireEvent.click(authorBtn);
    expect(rowTitles()[0]).toEqual(expect.stringContaining('The Stranger'));
    expect(onSortChange).toHaveBeenLastCalledWith({ key: 'author', direction: 'asc' });
  });

  it('sorts numerically with null pages last in both directions', () => {
    const { onSortChange } = setup();
    const pagesBtn = screen.getByRole('button', { name: 'Pages' });

    fireEvent.click(pagesBtn); // asc: 123, 256, 310, 412, 635, null
    expect(rowTitles()).toEqual([
      expect.stringContaining('The Stranger'),
      expect.stringContaining('Dune Messiah'),
      expect.stringContaining('The Hobbit'),
      expect.stringContaining('Dune'),
      expect.stringContaining('Moby-Dick'),
      expect.stringContaining('The Old Man and the Sea'),
    ]);
    expect(onSortChange).toHaveBeenLastCalledWith({ key: 'pages', direction: 'asc' });

    fireEvent.click(pagesBtn); // desc: 635, 412, 310, 256, 123, null last
    expect(rowTitles()).toEqual([
      expect.stringContaining('Moby-Dick'),
      expect.stringContaining('Dune'),
      expect.stringContaining('The Hobbit'),
      expect.stringContaining('Dune Messiah'),
      expect.stringContaining('The Stranger'),
      expect.stringContaining('The Old Man and the Sea'),
    ]);
  });

  it('keeps equal keys stable (herbert ties preserve data order)', () => {
    setup();
    const authorBtn = screen.getByRole('button', { name: 'Author' });
    fireEvent.click(authorBtn);
    // asc: ... herbert pair keeps b3 (Dune) before b5 (Dune Messiah)
    const asc = screen.getAllByRole('row');
    expect(asc[3].textContent).toContain('Dune');
    expect(asc[4].textContent).toContain('Dune Messiah');
    fireEvent.click(authorBtn);
    // desc: b2, b1, b3, b5, b6, b4 — the tied pair still keeps b3 before b5
    const desc = screen.getAllByRole('row');
    expect(desc[3].textContent).toContain('Dune');
    expect(desc[4].textContent).toContain('Dune Messiah');
  });

  it('gives non-sortable columns no button and no aria-sort', () => {
    const { onSortChange } = setup();
    expect(screen.queryByRole('button', { name: 'ID' })).toBeNull();
    expect(screen.getByRole('columnheader', { name: 'ID' }).getAttribute('aria-sort')).toBeNull();
    // clicking the header cell does nothing
    fireEvent.click(screen.getByRole('columnheader', { name: 'ID' }));
    expect(onSortChange).not.toHaveBeenCalled();
  });
});