// Sources/Runtime/SyncScheduler.swift
/*
 Coalesces re-syncs. A model change marks the nodes that read it dirty; one flush, queued on the
 main queue, syncs each dirty node once, parents first, which also re-registers their observation
 tracking. A node that left the tree since it was marked (its parent's sync removed it in the same
 flush) is skipped.
*/

import Dispatch

@MainActor
final class SyncScheduler {
    static let shared = SyncScheduler()

    private var dirty: [ObjectIdentifier: RenderNode] = [:]
    private var flushQueued = false

    /// Schedules `node` for a sync in the next flush.
    func markDirty(_ node: RenderNode) {
        dirty[ObjectIdentifier(node)] = node
        guard !flushQueued else { return }
        flushQueued = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated { SyncScheduler.shared.flush() }
        }
    }

    /// Syncs the dirty nodes, parents first. Nodes marked during the flush wait for the next one.
    func flush() {
        flushQueued = false
        let nodes = dirty.values.sorted { $0.depth < $1.depth }
        dirty = [:]
        for node in nodes where node.isAttached {
            node.sync()
        }
    }
}
