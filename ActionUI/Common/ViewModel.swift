// Common/ViewModel.swift
import SwiftUI
import Combine

/*
 ViewModel manages the state for a single view, including its value and validated properties.
*/

/// Context passed through the ViewModel when rendering a template instance.
/// When set, it signals that this view is being built as part of a data-driven template.
/// Views that need template-aware behavior (e.g. Button for action dispatch, containers for
/// child rendering) check `model.templateContext` to adjust their logic.
struct TemplateContext {
    let parentID: Int    // Container element ID — used as viewID in action dispatch
    let rowIndex: Int    // 0-based row index — used as viewPartID in action dispatch
    let row: [String]    // Column data for property substitution in nested children
}

/// Per-view auxiliary state that MOST views never touch. A plain Text or Slider view model leaves
/// this nil and carries a single pointer instead of a handful of empty collections; it is allocated
/// lazily the first time an element actually populates one of these fields - a template instance, a
/// container with runtime structural mutations, an in-flight pull-to-refresh, or a config-bearing
/// element. Keeping the odds and ends in one clearly-labeled bag stops view-specific state from
/// accreting on the hot `ViewModel` type. Reached only through `ViewModel`'s forwarding accessors,
/// so it inherits its main-actor isolation.
@MainActor
final class ViewModelExtras {
    // Set when rendering as a template instance.
    var templateContext: TemplateContext?
    // Container-keyed override of the element's static `subviews`. When a key is present here,
    // ActionUIRegistry.buildView merges it over the element's static container before passing the
    // element to view-specific construction. Populated by insertElement / insertRow / removeElement
    // so runtime structural mutations are observed without rewriting the immutable element graph.
    // Values are [ActionUIElement] for flat containers and [[ActionUIElement]] for row containers.
    var dynamicSubviews: [String: Any]?
    // Pull-to-refresh state (see ViewModel.endRefresh). A scrollable view's `.refreshable` action
    // suspends on `refreshContinuation` until the client signals done; `refreshSubtreeIDs` holds
    // this view and its descendant ids so a mutation to any of them ends the refresh. Both nil when
    // no refresh is in flight.
    var refreshContinuation: CheckedContinuation<Void, Never>?
    var refreshSubtreeIDs: Set<Int>?
    // The element's live NON-VISUAL config (see ActionUIElement's head comment): the document's
    // "config" block, plus any runtime overrides from setElementConfig. Stored verbatim - the
    // element's buildView is the one consumer and checks what it reads. Empty for the many elements
    // without a config block, which is why it lives here rather than inline on ViewModel.
    var config: [String: Any] = [:]
    // Top-level config keys set at RUNTIME by a host via setElementConfig (as opposed to parsed from
    // the document's "config" block). Lets an element distinguish host-provided config from
    // document-provided config for security decisions - e.g. whether a transport.command that would
    // spawn a subprocess was requested by trusted host code or by an untrusted document.
    var configInjectedKeys: Set<String> = []
}

// Public as a type so it can appear in the public ActionUIViewConstruction signatures that
// add-on element types implement. Only `value`, `states`, and the read side of `config`
// are public surface; the rest of the view-model machinery (validated properties,
// template context, refresh/insertion state) stays internal, and `init()` is internal so
// only the engine constructs view models.
@MainActor
public class ViewModel: ObservableObject {
    @Published public var value: Any?
    @Published public var states: [String: Any]
    var validatedProperties: [String: Any] // Non-published cache
    var elementType: String // View type name (e.g. "TextField", "Slider")
    var mutationToken: Int = 0 // Incremented on every external property/state/value mutation

    // Lazily-allocated bag of view-specific state most views never use (see ViewModelExtras).
    // Reads through the forwarding accessors below allocate nothing while nil; only a real write
    // materializes it. Keeping it private forces every access through those accessors.
    private var extras: ViewModelExtras?
    private var requireExtras: ViewModelExtras {
        if let extras {
            return extras
        }
        let created = ViewModelExtras()
        extras = created
        return created
    }

    // The element's live NON-VISUAL config (see ActionUIElement's head comment): the
    // document's "config" block, plus any runtime overrides from setElementConfig.
    // Stored verbatim - the element's buildView is the one consumer and checks what it
    // reads, so there is no central validation. Public read so element buildView
    // implementations (including add-ons) can consume it; written only by the engine.
    // Non-published like validatedProperties: mutations ring objectWillChange manually.
    public internal(set) var config: [String: Any] {
        get { extras?.config ?? [:] }
        set { requireExtras.config = newValue }
    }

    var templateContext: TemplateContext? { // Set when rendering as a template instance
        get { extras?.templateContext }
        set { requireExtras.templateContext = newValue }
    }

    // Container-keyed override of the element's static `subviews`; see ViewModelExtras. nil while
    // the parent has no dynamic mutations.
    var dynamicSubviews: [String: Any]? {
        get { extras?.dynamicSubviews }
        set { requireExtras.dynamicSubviews = newValue }
    }

    // Pull-to-refresh state; see ViewModelExtras and endRefresh. Both nil when no refresh is in
    // flight.
    var refreshContinuation: CheckedContinuation<Void, Never>? {
        get { extras?.refreshContinuation }
        set { requireExtras.refreshContinuation = newValue }
    }
    var refreshSubtreeIDs: Set<Int>? {
        get { extras?.refreshSubtreeIDs }
        set { requireExtras.refreshSubtreeIDs = newValue }
    }

    init() {
        self.value = nil
        self.states = [:]
        self.validatedProperties = [:]
        self.elementType = ""
    }

    // Records that `key` was set by a host at runtime (setElementConfig), not parsed from the document.
    func markConfigHostInjected(_ key: String) {
        requireExtras.configInjectedKeys.insert(key)
    }

    /// Whether the given top-level config key was set at runtime by a host via setElementConfig
    /// (rather than coming from the document's "config" block). Public so element implementations
    /// (including add-ons) can gate document-origin config for security decisions.
    public func isConfigHostInjected(_ key: String) -> Bool {
        extras?.configInjectedKeys.contains(key) ?? false
    }

    // Ends an in-flight pull-to-refresh, resuming the suspended `.refreshable` action so its
    // spinner retracts. Idempotent: a no-op when no refresh is in flight, so it is safe to
    // call from every client mutation and from the safety timeout.
    func endRefresh() {
        guard refreshSubtreeIDs != nil else { return }
        refreshSubtreeIDs = nil
        if let continuation = refreshContinuation {
            refreshContinuation = nil
            continuation.resume()
        }
    }

    // Validate properties for the given element, updating validatedProperties
    func validateProperties(for element: any ActionUIElementBase) {
        let registry = ActionUIRegistry.shared
        self.validatedProperties = registry.getValidatedProperties(element: element, model: self)
    }

    // Validate properties from a dictionary, typically for runtime updates
    func validateProperties(_ properties: [String: Any], elementType: String, logger: any ActionUILogger) {
        let registry = ActionUIRegistry.shared
        self.validatedProperties = registry.validateProperties(forElementType: elementType, properties: properties)
    }
}
