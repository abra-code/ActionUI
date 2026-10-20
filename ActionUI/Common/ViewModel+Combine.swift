// Common/ViewModel+Combine.swift
/*
 Combine publishers for a ViewModel's states and value, for Apple code (add-ons) that consumes
 changes as a publisher. Built on observeStates / observeValue: each publisher sends the current
 value when subscribed, then one element per change.
*/

import Combine

extension ViewModel {
    /// The current states, then every change.
    ///
    /// Each access makes a new publisher; subscribe to it once. Its registration lasts until the
    /// subscription is cancelled, or until the publisher is released if it is never subscribed.
    /// A second subscriber to the same publisher stops receiving when the first one cancels.
    public var statesPublisher: AnyPublisher<[String: Any], Never> {
        let subject = CurrentValueSubject<[String: Any], Never>(states)
        let observation = observeStates { subject.send($0) }
        return subject
            .handleEvents(receiveCancel: { observation.cancel() })
            .eraseToAnyPublisher()
    }

    /// The current value, then every change. The same lifetime rules as `statesPublisher`.
    public var valuePublisher: AnyPublisher<Any?, Never> {
        let subject = CurrentValueSubject<Any?, Never>(value)
        let observation = observeValue { subject.send($0) }
        return subject
            .handleEvents(receiveCancel: { observation.cancel() })
            .eraseToAnyPublisher()
    }
}
