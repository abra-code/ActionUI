//  TipBillSplitter - ActionUI Example (iOS host, UIKit lifecycle)
//
//  DISTINCTIVE: this app's foundation is UIKit (UIApplicationMain + AppDelegate
//  + SceneDelegate + UIViewController), NOT the SwiftUI App lifecycle. ActionUI
//  still renders SwiftUI views; we embed the rendered tree via a
//  UIHostingController inside a plain UIViewController. The point is to prove
//  ActionUI drops cleanly into a non-SwiftUI iOS shell.
//
//  The scene is wired in UIKitSceneDelegate.swift; the recompute logic lives in
//  TipLogic.swift and is shared verbatim with the AppKit (macOS) host.

import UIKit

@main
final class UIKitAppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Swift hosts must name the scene delegate module-qualified in Info.plist
        // (UISceneDelegateClassName = $(PRODUCT_MODULE_NAME).UIKitSceneDelegate).
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
