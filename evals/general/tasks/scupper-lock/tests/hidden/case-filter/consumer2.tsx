/*
 * Hidden consumer #2 — type-checks the public prop API with an uncontrolled
 * setup: defaultSort/defaultSelectedIds/defaultFilter, controlled-style event
 * callbacks, an align-typed column and a generic row type not used by any
 * fixture.
 *
 * This file is only compiled by `tsc` (strict) against /app/DataTable.tsx;
 * it is never executed.
 */
import * as React from 'react';
import { DataTable, ColumnDef, DataTableProps } from '../DataTable';

interface Invoice {
  number: string;
  total: number;
  paid: boolean;
}

const columns: ColumnDef<Invoice>[] = [
  { key: 'number', label: 'No.' },
  { key: 'total', label: 'Total', getValue: (i) => i.total, align: 'end' },
  { key: 'paid', label: 'Paid', getValue: (i) => (i.paid ? 'y' : 'n') },
];

const props: DataTableProps<Invoice> = {
  data: [
    { number: 'INV-1', total: 12.5, paid: false },
    { number: 'INV-2', total: 40, paid: true },
  ],
  columns,
  getRowId: (i, idx) => i.number || `row-${idx}`,
  selectionMode: 'multiple',
  defaultSelectedIds: [],
  defaultFilter: '2024',
  defaultSort: { key: 'total', direction: 'desc' },
  onSelectionChange: (ids: string[]) => {
    void ids;
  },
  onFilterChange: (text: string) => {
    void text;
  },
  sortable: false,
  searchable: true,
  navigable: false,
  className: 'ledger',
  getRowClassName: (i) => (i.paid ? 'ok' : undefined),
};

const element = <DataTable {...props} />;
void element;