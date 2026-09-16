/*
 * Hidden consumer #1 — type-checks the public prop API with a generic row
 * type that differs from every fixture dataset, an explicit generic JSX
 * usage, typed sort events and controlled single selection.
 *
 * This file is only compiled by `tsc` (strict) against /app/DataTable.tsx;
 * it is never executed.
 */
import * as React from 'react';
import {
  DataTable,
  ColumnDef,
  DataTableProps,
  SortDirection,
  SortState,
} from '../DataTable';

interface Company {
  id: string;
  name: string;
  revenue: number;
  region: string;
}

const columns: ColumnDef<Company>[] = [
  { key: 'id', label: 'ID', sortable: false },
  { key: 'name', label: 'Name', getValue: (c) => c.name, render: (c) => <b>{c.name}</b> },
  { key: 'revenue', label: 'Revenue', getValue: (c) => c.revenue, align: 'end' },
  { key: 'region', label: 'Region', headerClassName: 'region-head' },
];

const handleSort = (s: SortState): void => {
  void s;
};
const dir: SortDirection = 'asc';

const props: DataTableProps<Company> = {
  data: [{ id: 'c1', name: 'Acme', revenue: 10, region: 'EU' }],
  columns,
  getRowId: (c) => c.id,
  selectionMode: 'single',
  defaultSelectedIds: ['c1'],
  onSelectionChange: (ids: string[]) => {
    void ids;
  },
  defaultSort: { key: 'revenue', direction: 'desc' },
  onSortChange: handleSort,
  navigable: true,
  searchable: false,
  ariaLabel: 'Companies',
  getRowClassName: (c) => (c.region === 'EU' ? 'eu-row' : undefined),
};

// generic JSX instantiation must type-check (T inferred from props is Company)
const element = <DataTable<Company> {...props} />;
const brokenElement = dir === 'asc' ? element : null;
void brokenElement;