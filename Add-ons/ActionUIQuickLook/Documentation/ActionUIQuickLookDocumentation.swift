import Foundation

/// Resource bundle containing the ActionUIQuickLook add-on documentation:
/// the element schema doc (.md) and the JSON insert template.
///
/// Mirrors core `ActionUIDocumentation`: a resource-only product, so a client that links
/// `ActionUIQuickLookDocumentation` gets the add-on's docs copied into its bundle. Access at
/// runtime via `ActionUIQuickLookDocumentation.bundle`.
public enum ActionUIQuickLookDocumentation {
    public static let bundle = Bundle.module
}
