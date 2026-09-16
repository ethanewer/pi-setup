// store.ts — in-memory catalogue with cursor pagination.
// Ordering is stable: year ascending, ties broken by id ascending. The cursor
// is an opaque, URL-safe token that marks the *last delivered* item, so pages
// can never drift when items are added between requests.
import type { MediaCreate, MediaItem, MediaUpdate } from "./schemas";

const CURSOR_RE = /^[A-Za-z0-9._~-]{1,300}$/;

function encodeCursor(item: MediaItem): string {
  return Buffer.from(JSON.stringify({ year: item.year, id: item.id }), "utf8")
    .toString("base64url");
}

function decodeCursor(raw: string): { year: number; id: number } {
  if (!CURSOR_RE.test(raw)) {
    throw new Error("malformed cursor");
  }
  let text: string;
  try {
    text = Buffer.from(raw, "base64url").toString("utf8");
  } catch {
    throw new Error("malformed cursor");
  }
  let value: unknown;
  try {
    value = JSON.parse(text);
  } catch {
    throw new Error("malformed cursor");
  }
  const v = value as { year?: unknown; id?: unknown };
  if (
    typeof v.year !== "number" ||
    !Number.isSafeInteger(v.year) ||
    typeof v.id !== "number" ||
    !Number.isSafeInteger(v.id) ||
    v.id < 1
  ) {
    throw new Error("malformed cursor");
  }
  return { year: v.year, id: v.id };
}

export type Page = {
  items: MediaItem[];
  next_cursor: string | null;
  total: number;
};

export class MediaStore {
  private items: MediaItem[] = [];
  private nextId = 1;

  constructor(seed: MediaCreate[]) {
    for (const entry of seed) {
      this.add(entry);
    }
  }

  add(input: MediaCreate): MediaItem {
    const item: MediaItem = { id: this.nextId, ...input };
    this.nextId += 1;
    this.items.push(item);
    return item;
  }

  get(id: number): MediaItem | undefined {
    return this.items.find((it) => it.id === id);
  }

  update(id: number, patch: MediaUpdate): MediaItem | undefined {
    const item = this.items.find((it) => it.id === id);
    if (!item) {
      return undefined;
    }
    for (const key of ["title", "year", "rating", "medium"] as const) {
      if (patch[key] !== undefined) {
        (item as Record<string, unknown>)[key] = patch[key];
      }
    }
    if (patch.tags !== undefined) {
      item.tags = patch.tags;
    }
    return item;
  }

  /**
   * Returns one page of the catalogue.
   * @param cursor opaque token of the last item of the previous page.
   * @throws Error when the cursor does not decode (caller maps to 400).
   */
  list(limit: number, cursor?: string): Page {
    const sorted = [...this.items].sort((a, b) =>
      a.year - b.year !== 0 ? a.year - b.year : a.id - b.id
    );
    let start = 0;
    if (cursor !== undefined && cursor !== "") {
      const key = decodeCursor(cursor);
      let i = 0;
      while (
        i < sorted.length &&
        (sorted[i].year < key.year ||
          (sorted[i].year === key.year && sorted[i].id <= key.id))
      ) {
        i += 1;
      }
      start = i;
    }
    const page = sorted.slice(start, start + limit);
    const end = start + page.length;
    const next_cursor =
      end < sorted.length ? encodeCursor(sorted[end - 1]) : null;
    return { items: page, next_cursor, total: sorted.length };
  }
}