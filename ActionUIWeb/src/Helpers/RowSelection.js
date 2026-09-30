// RowSelection.js - which row stays selected when the rows of a data-driven Table or
// List change (Views/List.buildDataRows and Views/Table). Mirrors the Swift
// ActionUIModel.reconciledSelection and the Android ActionUIModel.reconciledSelection,
// so all hosts keep the same row.
//
// A row the selection still equals keeps it. Otherwise a row with the same first
// column (the row's identity) takes its place, with its new columns: a refresh that
// changes another column keeps the row selected. When several rows share that first
// column, the one at the same place among them is taken (the second "Alice" stays the
// second). With no such row the selection clears. Cells compare as strings, a
// missing cell as "" (as the tab-joined selection value shows it).

const cellText = (cell) => String(cell ?? "");
const sameRow = (a, b) =>
    a.length === b.length && a.every((cell, i) => cellText(cell) === cellText(b[i]));

// selected: the selected row's columns ([] = none); oldRows / rows: the rows before
// and after the change. Returns the row to select ([] = none).
export function reconciledSelection(selected, oldRows, rows) {
    if (selected.length === 0 || rows.some((row) => sameRow(row, selected))) return selected;
    const first = cellText(selected[0]);
    const isPeer = (row) => row.length > 0 && cellText(row[0]) === first;
    const place = Math.max(0, oldRows.filter(isPeer).findIndex((row) => sameRow(row, selected)));
    const peers = rows.filter(isPeer);
    return place < peers.length ? peers[place] : [];
}
