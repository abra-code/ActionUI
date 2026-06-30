import Foundation

/// Resource bundle containing the ActionUIChat add-on documentation:
/// the element schema doc (.md) and the JSON insert template.
///
/// Mirrors core `ActionUIDocumentation`: a resource-only product, so a client that links
/// `ActionUIChatDocumentation` gets the add-on's docs copied into its bundle. Access at
/// runtime via `ActionUIChatDocumentation.bundle`.
public enum ActionUIChatDocumentation {
    public static let bundle = Bundle.module
}
