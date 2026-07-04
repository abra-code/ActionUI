import Foundation

/// Resource bundle containing the ActionUIDiff add-on documentation:
/// the element schema doc (.md) and the JSON insert template.
///
/// Mirrors core `ActionUIDocumentation`: a resource-only product, so a client that links
/// `ActionUIDiffDocumentation` gets the add-on's docs copied into its bundle. Access at
/// runtime via `ActionUIDiffDocumentation.bundle`.
public enum ActionUIDiffDocumentation {
    public static let bundle = Bundle.module
}
