// RowKeyboardNav.js - the listbox/grid arrow-key selection pattern, shared by the
// selectable row containers (List both modes, NavigationSplitView sidebar, Table).
//
// A custom listbox (role="listbox"/"option", which List and NSV declare) or a
// selectable table must implement its own arrow keys: browsers only do it for the
// native <select>. Without it, an unhandled ArrowDown on a focused row falls through
// to its default action - scrolling the nearest scroll ancestor - which reads as the
// scroller "capturing" the key. This is the WAI-ARIA Authoring Practices keyboard
// interaction for a single-select, focus-follows-selection listbox: Down/Up move to
// the next/previous row, Home/End to the first/last; the row is selected and focused
// (focusing scrolls it into view), and the key's default scroll is suppressed.
//
// Pure control flow (no DOM of its own): the caller passes the focused row's current
// `index`, the row `count`, and a `moveTo(targetIndex)` that selects the target as a
// user action and focuses its node. Returns true when it handled (and consumed) an
// arrow / Home / End key, so the caller can stop.

export function navigateRowsOnKey(event, index, count, moveTo) {
    if (count <= 0) return false;
    let target;
    switch (event.key) {
        case "ArrowDown": target = Math.min(index + 1, count - 1); break;
        case "ArrowUp": target = Math.max(index - 1, 0); break;
        case "Home": target = 0; break;
        case "End": target = count - 1; break;
        default: return false;
    }
    event.preventDefault(); // suppress the default scroll of the wrapping scroller
    if (target !== index && target >= 0) moveTo(target);
    return true;
}
