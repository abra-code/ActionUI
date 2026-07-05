import Foundation

/// Resource bundle containing the ActionUIRichText add-on documentation:
/// the element schema doc (.md) and the JSON insert template.
///
/// Mirrors core `ActionUIDocumentation`: a resource-only product, so a client that links
/// `ActionUIRichTextDocumentation` gets the add-on's docs copied into its bundle. Access at
/// runtime via `ActionUIRichTextDocumentation.bundle`.
public enum ActionUIRichTextDocumentation {
    public static let bundle = Bundle.module
}
