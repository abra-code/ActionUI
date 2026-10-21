// Core/ActionUIRegistry+Test.swift
@testable import ActionUI

extension ActionUIRegistry {
    // Back to the built-in elements alone: loadBuiltIns replaces the spec table and the renderer
    // half's own table, so add-on registrations go.
    func resetForTesting() {
        loadBuiltIns()
    }
}
