//
//  ActionUITestApp.swift
//  ActionUITestApp
//
//  Created by Tomasz Kukielka on 9/5/25.
//

import SwiftUI
import ActionUI

@main
struct ActionUITestAppApp: App {
    var body: some Scene {
        WindowGroup {
//          ContentView()
            ActionUIContentView(resourceName: "ContentView", resourceExtension: "json")
//          ActionUIContentView(networkURL: URL(string: "https://example.com/ContentView.json")!)
        }
    }
}
