// Sources/Runtime/SyncScheduler.swift
/*
 Coalesces re-syncs. A model change marks the nodes that read it dirty; one flush, queued on the
 main queue, syncs each dirty node once, parents first, which also re-registers their observation
 tracking. A node that left the tree since it was marked (its parent's sync removed it in the same
 flush) is skipped.

 Nodes marked while the flush runs (the children of a node whose environment changed) are synced in
 the same flush, in further rounds, so a change reaches every level before GTK draws a frame. The
 rounds are capped, so a renderer that keeps marking nodes dirty cannot hold the main loop; what is
 left waits for the next flush.
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

    /// The most rounds one flush runs.
    static let maximumRounds = 64

    /// Syncs the dirty nodes, parents first, and those they mark dirty, in rounds.
    func flush() {
        var rounds = 0
        repeat {
            flushQueued = false
            let nodes = dirty.values.sorted { $0.depth < $1.depth }
            dirty = [:]
            for node in nodes where node.isAttached {
                node.sync()
            }
            rounds += 1
        } while !dirty.isEmpty && rounds < Self.maximumRounds
    }
}
