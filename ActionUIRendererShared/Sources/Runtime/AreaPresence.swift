// Sources/Runtime/AreaPresence.swift
/*
 Whether the pointer, or a drag, is over an element made of several areas (its frame and its
 overlay view: NodeDecorations.pointerAreas): over any of them is over the element. GTK reports
 leaving one area and entering the next as two events, so the presence settles on the main queue's
 next turn, as SwiftUI reports onHover and isTargeted from a Task, and is reported only when it
 changed (NodeHover, NodeDrop). An enter and a leave within one turn report nothing.
*/

import Dispatch

@MainActor
final class AreaPresence {
    private var inside: Set<Int> = []
    private var reported = false
    private var pending = false
    private let report: @MainActor (Bool) -> Void

    /// `report` gets the presence each time it settles changed.
    init(report: @escaping @MainActor (Bool) -> Void) {
        self.report = report
    }

    func entered(_ area: Int) {
        inside.insert(area)
        settle()
    }

    func left(_ area: Int) {
        inside.remove(area)
        settle()
    }

    private func settle() {
        guard !pending else { return }
        pending = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pending = false
                let present = !self.inside.isEmpty
                guard present != self.reported else { return }
                self.reported = present
                self.report(present)
            }
        }
    }
}
