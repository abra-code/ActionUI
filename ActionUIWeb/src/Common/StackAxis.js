// StackAxis.js — shared stack layout vocabulary.
// Web analog of ActionUI/Common/StackAxis.kt (Android).
//
// SwiftUI infers some elements' orientation from their enclosing stack — most
// notably Divider, which is a horizontal rule inside a VStack and a vertical
// rule inside an HStack. The DOM has no such inference, so a stack tags its
// root with `data-aui-axis` and orientation-sensitive children (Divider) read
// the nearest ancestor's axis. The root default is "vertical", so a stack-less
// top-level Divider renders as a horizontal rule, matching SwiftUI.

export const StackAxis = Object.freeze({
    Vertical: "vertical",
    Horizontal: "horizontal",
});

// Cross-axis alignment maps. SwiftUI's VStack aligns children horizontally;
// its HStack aligns them vertically. Both default to center (matching SwiftUI,
// whose stack default is .center even though flexbox/Compose default elsewhere).
export const COLUMN_ALIGN = { leading: "flex-start", center: "center", trailing: "flex-end" };
export const ROW_ALIGN = {
    top: "flex-start", center: "center", bottom: "flex-end",
    firstTextBaseline: "baseline", lastTextBaseline: "last baseline",
};

export const DEFAULT_SPACING = 8; // approximates SwiftUI's adaptive default spacing

// Resolves the active axis for an orientation-sensitive child by walking up to
// the nearest stack root. Defaults to Vertical when there is no enclosing stack.
export function nearestStackAxis(node) {
    const stack = node.closest?.("[data-aui-axis]");
    return stack?.dataset.auiAxis ?? StackAxis.Vertical;
}
