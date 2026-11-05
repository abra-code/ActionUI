import Foundation

/// Resource bundle containing the ActionUIHostSurface add-on documentation:
/// the element schema doc (.md) and the JSON insert template.
///
/// Mirrors core `ActionUIDocumentation`: a resource-only product, so a client that links
/// `ActionUIHostSurfaceDocumentation` gets the add-on's docs copied into its bundle. Access at
/// runtime via `ActionUIHostSurfaceDocumentation.bundle`.
public enum ActionUIHostSurfaceDocumentation {
    public static let bundle = Bundle.module
}
