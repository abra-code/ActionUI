// Sources/Runtime/RemoteImages.swift
/*
 Images loaded from URLs (AsyncImage), decoded into GdkTextures and kept by URL, so a URL shown in
 several places, or shown again, loads once while it stays in memory.

 - Loading goes through URLLoader; decoding (gdk_texture_new_from_bytes, which GTK documents as
   thread-safe) runs off the main thread, so a large photo does not stall the window.
 - The textures kept are bounded by their pixel bytes (budget); past it the least recently used
   go. A widget showing a texture holds its own reference, so dropping one here hides nothing.
 - A failed load is not kept: whoever asked decides whether to ask again (an AsyncImage asks
   again only for a new URL), so a URL that fails is not retried in a loop.
*/

import CAdwaita

/// A GdkTexture, released with the last Swift reference. Textures are immutable, so one decoded
/// on another thread can be handed to the main thread.
final class LoadedTexture: @unchecked Sendable {
    let pointer: OpaquePointer

    init(adopting pointer: OpaquePointer) {
        self.pointer = pointer
    }

    /// Its pixels' size in bytes, four per pixel: what it costs to keep.
    var cost: Int {
        Int(gdk_texture_get_width(pointer)) * Int(gdk_texture_get_height(pointer)) * 4
    }

    deinit {
        g_object_unref(UnsafeMutableRawPointer(pointer))
    }
}

@MainActor
final class RemoteImages {
    static let shared = RemoteImages()

    /// The most pixel bytes the textures kept may take.
    var budget = 64 << 20

    private struct Kept {
        let texture: LoadedTexture
        var lastUse: UInt64
    }

    private var kept: [String: Kept] = [:]
    /// The URLs loading now, with whoever waits for each.
    private var waiting: [String: [@MainActor (Bool) -> Void]] = [:]
    private var useCounter: UInt64 = 0

    /// The texture for `url` when it has loaded and is still kept; nil otherwise.
    func texture(_ url: String) -> LoadedTexture? {
        guard var entry = kept[url] else { return nil }
        useCounter &+= 1
        entry.lastUse = useCounter
        kept[url] = entry
        return entry.texture
    }

    /// Loads `url` unless it is loading already; `done` runs once on the main thread, with true
    /// when the texture is kept (also when it was kept before this call) and false when the URL
    /// gave no image.
    func load(_ url: String, then done: @escaping @MainActor (Bool) -> Void) {
        if kept[url] != nil {
            _ = runAfter(milliseconds: 0) { done(true) }
            return
        }
        if waiting[url] != nil {
            waiting[url]?.append(done)
            return
        }
        waiting[url] = [done]
        URLLoader.fetch(url) { bytes in
            guard let bytes else { return self.finish(url, nil) }
            Task.detached {
                let texture = Self.decode(bytes)
                await MainActor.run { self.finish(url, texture) }
            }
        }
    }

    /// The image the bytes hold, nil when GTK cannot decode them. Runs off the main thread.
    nonisolated private static func decode(_ bytes: LoadedBytes) -> LoadedTexture? {
        var error: UnsafeMutablePointer<GError>?
        let texture = gdk_texture_new_from_bytes(bytes.bytes, &error)
        if let error { g_error_free(error) }
        return texture.map { LoadedTexture(adopting: $0) }
    }

    private func finish(_ url: String, _ texture: LoadedTexture?) {
        if let texture {
            useCounter &+= 1
            kept[url] = Kept(texture: texture, lastUse: useCounter)
            trim(keeping: url)
        }
        let waiters = waiting.removeValue(forKey: url) ?? []
        for done in waiters {
            done(texture != nil)
        }
    }

    /// Drops the least recently used textures until the rest fit the budget; `url`, just loaded,
    /// stays even when it alone is over it.
    private func trim(keeping url: String) {
        var total = kept.values.reduce(0) { $0 + $1.texture.cost }
        guard total > budget else { return }
        for (other, entry) in kept.sorted(by: { $0.value.lastUse < $1.value.lastUse }) where other != url {
            kept[other] = nil
            total -= entry.texture.cost
            if total <= budget { break }
        }
    }

    /// Forgets every texture kept (for tests).
    func removeAll() {
        kept = [:]
    }
}
