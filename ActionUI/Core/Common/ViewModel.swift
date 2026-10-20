// Core/Common/ViewModel.swift
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Observation

/*
 ViewModel manages the state for a single view, including its value and current properties.
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

/// A scope in which ViewModel reads are not reported to Observation.
///
/// A description can load while a view renders: a host builds `FileLoadableView` in a window's
/// content, and a LoadableView element loads its file from `buildView`. Loading creates the view
/// models and runs each element's initialValue and initialStates, which read the new models. Were
/// those reads tracked, the rendering view would depend on every new model, a later host write
/// (rows set on a List, say) would render it again, and rendering it again loads the description
/// again, replacing the models and losing the write. A container building a template row reads
/// the row's throw-away model in the same scope (see TemplateHelper.buildTemplateView).
@MainActor
enum UntrackedReads {
    private static var depth = 0

    static var isActive: Bool { depth > 0 }

    static func perform<T>(_ body: () throws -> T) rethrows -> T {
        depth += 1
        defer { depth -= 1 }
        return try body()
    }
}

/// Per-view auxiliary state that MOST views never touch. A plain Text or Slider view model leaves
/// this nil and carries a single pointer instead of a handful of empty collections; it is allocated
/// lazily the first time an element actually populates one of these fields - a template instance, an
/// in-flight pull-to-refresh, or an element's render cache. Not observed: nothing here is meant to
/// re-render a view, and Chart writes its cache while rendering. Keeping the odds and
/// ends in one clearly-labeled bag stops view-specific state from
/// accreting on the hot `ViewModel` type. Reached only through `ViewModel`'s forwarding accessors,
/// so it inherits its main-actor isolation.
@MainActor
final class ViewModelExtras {
    // Set when rendering as a template instance.
    var templateContext: TemplateContext?
    // Pull-to-refresh state (see ViewModel.endRefresh). A scrollable view's `.refreshable` action
    // suspends on `refreshContinuation` until the client signals done; `refreshSubtreeIDs` holds
    // this view and its descendant ids so a mutation to any of them ends the refresh. Both nil when
    // no refresh is in flight.
    var refreshContinuation: CheckedContinuation<Void, Never>?
    var refreshSubtreeIDs: Set<Int>?
    // An element's private render cache (Chart keeps its parsed description and built marks
    // here). Not observed: writing it from a view body triggers no update, and it dies with
    // the view model when the element is removed.
    var elementCache: AnyObject?
}

// Public as a type so it can appear in the public ActionUIViewConstruction signatures that
// add-on element types implement. Only `value` and `states` are public surface; the rest of the
// view-model machinery (current properties,
// template context, refresh/insertion state) stays internal, and `init()` is internal so
// only the engine constructs view models.
//
// Observable by hand rather than through the @Observable macro: a getter reports its read to
// Observation only outside UntrackedReads.perform, which the description loader and template rows
// use (see UntrackedReads). The tracked properties are value, states, properties, hasProperties,
// mutationToken and dynamicSubviews; the rest are plain stored properties.
@MainActor
public final class ViewModel: Observable {
    private let registrar = ObservationRegistrar()

    private var storedValue: Any?
    public var value: Any? {
        get { track(\.value); return storedValue }
        set {
            registrar.withMutation(of: self, keyPath: \.value) { storedValue = newValue }
            valueObservers?.notify(newValue)
        }
    }

    private var storedStates: [String: Any]
    public var states: [String: Any] {
        get { track(\.states); return storedStates }
        set {
            registrar.withMutation(of: self, keyPath: \.states) { storedStates = newValue }
            statesObservers?.notify(newValue)
        }
    }

    // The handlers of observeValue and observeStates (ViewModel+Observers.swift), created by the
    // first registration: most view models are never observed this way.
    var valueObservers: ObserverList<Any?>?
    var statesObservers: ObserverList<[String: Any]>?

    // The element's current properties: its JSON properties plus every change made through
    // ActionUIModel.setElementProperty. Renderers, getElementProperty and the element's
    // initialValue read this.
    private var storedProperties: [String: Any]
    var properties: [String: Any] {
        get { track(\.properties); return storedProperties }
        set { registrar.withMutation(of: self, keyPath: \.properties) { storedProperties = newValue } }
    }

    // False until seedProperties runs (a load, or a template row); then `properties` is the store.
    private var storedHasProperties = false
    private(set) var hasProperties: Bool {
        get { track(\.hasProperties); return storedHasProperties }
        set { registrar.withMutation(of: self, keyPath: \.hasProperties) { storedHasProperties = newValue } }
    }

    var elementType: String // View type name (e.g. "TextField", "Slider")

    // Incremented on every external property/state/value mutation.
    private var storedMutationToken = 0
    var mutationToken: Int {
        get { track(\.mutationToken); return storedMutationToken }
        set { registrar.withMutation(of: self, keyPath: \.mutationToken) { storedMutationToken = newValue } }
    }

    private func track<Member>(_ keyPath: KeyPath<ViewModel, Member>) {
        if !UntrackedReads.isActive {
            registrar.access(self, keyPath: keyPath)
        }
    }

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

    var templateContext: TemplateContext? { // Set when rendering as a template instance
        get { extras?.templateContext }
        set { requireExtras.templateContext = newValue }
    }

    // Container-keyed override of the element's static `subviews`. When a key is present here,
    // ActionUIRegistry.buildView merges it over the element's static container before passing the
    // element to view-specific construction. Populated by insertElement / insertRow / removeElement
    // so runtime structural mutations are observed without rewriting the immutable element graph.
    // Values are [ActionUIElement] for flat containers and [[ActionUIElement]] for row containers.
    // nil while the parent has no dynamic mutations. Tracked: containers read it while rendering.
    private var storedDynamicSubviews: [String: Any]?
    var dynamicSubviews: [String: Any]? {
        get { track(\.dynamicSubviews); return storedDynamicSubviews }
        set { registrar.withMutation(of: self, keyPath: \.dynamicSubviews) { storedDynamicSubviews = newValue } }
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

    // An element's private render cache; see ViewModelExtras.
    var elementCache: AnyObject? {
        get { extras?.elementCache }
        set { requireExtras.elementCache = newValue }
    }

    init() {
        self.storedStates = [:]
        self.storedProperties = [:]
        self.elementType = ""
    }

    // Sets the element's properties as loaded (or as substituted for a template row).
    func seedProperties(_ properties: [String: Any]) {
        self.properties = properties
        hasProperties = true
    }

    // Reads every tracked property but hasProperties (seedProperties writes properties with it), so
    // the view whose body calls it renders again on any change to this model, as views did when
    // they held the model as an ObservedObject. A view that reads only what it shows does not need it.
    func trackAllChanges() {
        _ = value
        _ = states
        _ = properties
        _ = mutationToken
        _ = dynamicSubviews
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
}
