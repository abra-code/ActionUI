// Common/ViewModel+Observers.swift
/*
 Change observers for a ViewModel's value and states, for code outside a render that must see
 every change: a host channel that receives one appended item at a time, an add-on's bridge to
 its own component. A view that only needs to show the current value reads the model in its
 body instead.

 Each observer is called once with the current value when it registers, then once per change,
 synchronously and in registration order, with no coalescing.
*/

/// A registration that stops delivering when cancelled or released.
///
/// Not main-actor isolated, so it can be released on any thread (a deinit cannot be isolated on
/// ActionUI's minimum systems); cancelling only removes the handler.
/// A cancel on another thread can still be followed by one delivery that had already started.
public final class ActionUIObservation: Sendable {
    private let stop: @Sendable () -> Void

    init(stop: @escaping @Sendable () -> Void) {
        self.stop = stop
    }

    /// Stops the deliveries. Calling it again does nothing.
    public func cancel() {
        stop()
    }

    deinit {
        stop()
    }
}

/// The handlers registered for one ViewModel property. `add` and `remove` may run on any thread;
/// `notify` runs on the main actor, from the property's observer, and calls the handlers outside
/// the lock, so a handler may register or cancel observations.
final class ObserverList<Value>: @unchecked Sendable {
    typealias Handler = @MainActor (Value) -> Void

    private let lock = Lock()
    private var handlers: [Int: Handler] = [:]
    private var nextToken = 0

    func add(_ handler: @escaping Handler) -> Int {
        lock.withLock {
            nextToken += 1
            handlers[nextToken] = handler
            return nextToken
        }
    }

    func remove(_ token: Int) {
        // The handler is returned and released after the lock is dropped: its captures may own
        // another observation of this list, whose deinit takes the lock again.
        _ = lock.withLock {
            handlers.removeValue(forKey: token)
        }
    }

    @MainActor
    func notify(_ value: Value) {
        let tokens = lock.withLock {
            handlers.keys.sorted()
        }
        for token in tokens {
            // Looked up again for each call, so a handler that an earlier one cancelled is not called.
            guard let handler = lock.withLock({ handlers[token] }) else {
                continue
            }
            handler(value)
        }
    }

    /// The number of registered handlers.
    var count: Int {
        lock.withLock { handlers.count }
    }
}

extension ViewModel {
    /// Calls `handler` now with the current states, then after every change: one call per
    /// change, in the order changes are made.
    public func observeStates(_ handler: @escaping @MainActor ([String: Any]) -> Void) -> ActionUIObservation {
        let list = statesObservers ?? ObserverList()
        statesObservers = list
        return Self.observe(list, current: states, handler)
    }

    /// Calls `handler` now with the current value, then after every change: one call per change,
    /// in the order changes are made.
    public func observeValue(_ handler: @escaping @MainActor (Any?) -> Void) -> ActionUIObservation {
        let list = valueObservers ?? ObserverList()
        valueObservers = list
        return Self.observe(list, current: value, handler)
    }

    private static func observe<Value>(
        _ list: ObserverList<Value>, current: Value, _ handler: @escaping @MainActor (Value) -> Void
    ) -> ActionUIObservation {
        // Registered before the first call, so a change the handler itself makes reaches it too.
        let token = list.add(handler)
        handler(current)
        return ActionUIObservation { list.remove(token) }
    }
}
