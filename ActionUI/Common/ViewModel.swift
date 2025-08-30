// Common/ViewModel.swift
import SwiftUI
internal import Combine

@MainActor
class ViewModel: ObservableObject {
    @Published var properties: [String: Any]
    @Published var validatedProperties: [String: Any]
    @Published var value: Any?
    @Published var states: [String: Any]

    init(properties: [String: Any]) {
        self.properties = properties
        self.validatedProperties = [:]
        self.states = [:]
    }
}
