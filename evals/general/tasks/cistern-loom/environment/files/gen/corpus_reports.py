# -*- coding: utf-8 -*-
"""reports/ modules of the cistern corpus (legacy loose style)."""

CREPORTS = [
    ("src/reports/rows.ts", """// rows.ts: text table rendering shared by the report writers. Columns
// align to their widest cell; separators use Unicode box characters so
// generated artefacts diff cleanly across platforms.

export interface Column {
  readonly title: string;
  readonly align: "left" | "right";
}

export interface Cell {
  readonly text: string;
}

export type Row = readonly Cell[];

/** Build an aligned text table from a title row and data rows. */
export function renderTable(columns«A:readonly Column[]», rows«A: readonly Row[]»)«A:string» {
  const widths: number[] = [];
  for (let c = 0; c < columns.length; c += 1) {
    const col = columns[c];
    if (col === undefined) {
      continue;
    }
    let w = col.title.length;
    for (const r of rows) {
      const cell = r[c];
      const len = cell === undefined ? 0 : cell.text.length;
      if (len > w) {
        w = len;
      }
    }
    widths[c] = w;
  }
  const header = columns.map((col, c) => pad(col.title, widths[c] ?? 0, "right")).join(" | ");
  const line = widths.map((w) => "-".repeat(w)).join("-+-");
  const body = rows.map((r) => renderRow(r, columns, widths)).join("\\n");
  return [header, line, body].join("\\n");
}

function renderRow(r: readonly Cell[], columns: readonly Column[], widths: readonly number[]): string {
  return columns
    .map((col, c) => {
      const cell = r[c];
      const text = cell === undefined ? "" : cell.text;
      return pad(text, widths[c] ?? 0, col.align);
    })
    .join(" | ");
}

/** Pad to width with the given alignment. */
export function pad(text«A:string», width«A:number», align«A:"left" | "right"»)«A:string» {
  if (text.length >= width) {
    return text;
  }
  const fill = " ".repeat(width - text.length);
  return align === "right" ? fill + text : text + fill;
}

/** Format a number with thousands separators. */
export function format(n«A:number»)«A:string» {
  const neg = n < 0;
  const digits = Math.abs(n).toString();
  const parts: string[] = [];
  for (let i = digits.length; i > 0; i -= 3) {
    parts.unshift(digits.slice(Math.max(0, i - 3), i));
  }
  return (neg ? "-" : "") + parts.join(",");
}

/** Row of a report section with a section label. */
export interface Section {
  readonly title: string;
  readonly rows: readonly Row[];
}

"""),
]