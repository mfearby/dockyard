// Pure helpers for drag-to-reorder. Kept free of DOM access so they can be unit tested.

/** Where a dragged item lands, and how far it is drawn from its start (clamped to the bar's ends). */
export function dragTarget(from: number, dx: number, step: number, count: number): { to: number; offset: number } {
  const offset = Math.max(-from * step, Math.min((count - 1 - from) * step, dx));
  const to = Math.max(0, Math.min(count - 1, Math.round(from + offset / step)));
  return { to, offset };
}

/** How far item `j` slides to make room while the item at `from` hovers over `to`. */
export function shiftFor(j: number, from: number, to: number, step: number): number {
  if (from < to && j > from && j <= to) return -step;
  if (from > to && j >= to && j < from) return step;
  return 0;
}

/** Returns a copy of `items` with the element at `from` moved to `to`. */
export function moveItem<T>(items: readonly T[], from: number, to: number): T[] {
  const copy = items.slice();
  const [item] = copy.splice(from, 1);
  copy.splice(to, 0, item);
  return copy;
}

/** Sorts items by their position in `order`; items not in `order` keep their relative order at the end. */
export function applyOrder<T extends { bundleId: string }>(items: readonly T[], order: readonly string[]): T[] {
  const rank = new Map(order.map((id, i) => [id, i]));
  return items
    .map((item, i) => ({ item, i, r: rank.get(item.bundleId) ?? Infinity }))
    .sort((a, b) => a.r - b.r || a.i - b.i)
    .map((x) => x.item);
}
