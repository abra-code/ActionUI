// RowDiff.js - the shared incremental-rows diff for the data-driven row repeaters
// (Helpers/TemplateHelper.renderTemplateRows and Views/List.buildDataRows).
//
// The rows API (ActionUI.setElementRows / appendElementRows / clearElementRows)
// funnels every change through setElementState("content", fullArray) - and
// appendElementRows re-sends the whole concatenated array - so a naive consumer
// rebuilds the entire list on every change (an O(n) replaceChildren per append, the
// streaming hot path). commonRowPrefix lets a consumer rebuild only from the first
// row that actually changed: the append case (next = old + tail) keeps the whole old
// prefix in place and builds just the tail; a truncation drops the tail; a prepend or
// a mid-list edit degrades to rebuild-from-the-first-change (append / clear are the
// hot paths, prepend is rare). Rows are [[String]] (the Apple states["content"]
// contract), so equality is a shallow per-column compare.
//
// Note on baked indices: the repeaters bake each row's index into its built node
// (the template column substitution context, the List row's click/dblclick
// handlers). Rebuilding from the first change re-bakes the shifted indices, and an
// unchanged prefix row keeps the index it was built with - so the prefix diff is
// index-correct as long as the prefix rows are positionally unchanged (which is
// exactly what commonRowPrefix guarantees).

// Shallow [[String]] row equality (same length, same column values).
export function rowsEqual(a, b) {
    if (a === b) return true;
    if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
        if (a[i] !== b[i]) return false;
    }
    return true;
}

// The number of equal leading rows shared by `oldRows` and `nextRows` - the count a
// consumer can keep in place and rebuild after.
export function commonRowPrefix(oldRows, nextRows) {
    const min = Math.min(oldRows.length, nextRows.length);
    let i = 0;
    while (i < min && rowsEqual(oldRows[i], nextRows[i])) i++;
    return i;
}
