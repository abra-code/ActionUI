import Foundation

/// Resource bundle containing the ActionUICachedImage add-on documentation:
/// the element schema doc (.md) and the JSON insert template.
///
/// Mirrors core `ActionUIDocumentation`: a resource-only product, so a client that links
/// `ActionUICachedImageDocumentation` gets the add-on's docs copied into its bundle. Access at
/// runtime via `ActionUICachedImageDocumentation.bundle`.
public enum ActionUICachedImageDocumentation {
    public static let bundle = Bundle.module
}
