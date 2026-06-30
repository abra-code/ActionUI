//  TipBillSplitter - ActionUI Example (iOS host, UIKit lifecycle)
//
//  The scene delegate is where ActionUI is hosted on iOS. We embed the
//  ActionUI-rendered SwiftUI tree (a UIHostingController) inside a plain
//  UIViewController via the child-VC dance, then make that the window root -
//  driving home that the app shell is UIKit, not SwiftUI.

import UIKit
import SwiftUI
import ActionUI
import ActionUISwiftAdapter

final class UIKitSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        window = UIWindow(windowScene: windowScene)

        // (windowUUID, viewID) addresses every element. Mint one per window.
        let windowUUID = UUID().uuidString

        // (2) Register the single recompute handler (shared with the AppKit host).
        ActionUISwift.registerActionHandler(actionID: "tip.recompute") { _, win, _, _, _ in
            MainActor.assumeIsolated { TipBillSplitter.recompute(win) }
        }

        // (1) Load the bundled shared JSON and host it via UIHostingController.
        let container = TipContainerViewController()
        if let url = Bundle.main.url(forResource: "TipBillSplitter", withExtension: "json") {
            let hosting = ActionUISwift.loadHostingController(from: url, windowUUID: windowUUID, isContentView: true)
            container.embed(hosting)
            // Seed the outputs from the JSON's initial input values.
            TipBillSplitter.recompute(windowUUID)
        } else {
            container.showMessage("TipBillSplitter.json missing from the app bundle")
        }

        window?.rootViewController = container
        window?.makeKeyAndVisible()
    }
}

// A plain UIKit view controller that embeds the ActionUI hosting controller as a
// child (addChild / addSubview / didMove). This is the "embed inside your own
// UIViewController" path from the host-patterns doc.
final class TipContainerViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
    }

    func embed(_ hosting: UIViewController) {
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)
        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
        hosting.didMove(toParent: self)
    }

    func showMessage(_ message: String) {
        let label = UILabel()
        label.text = message
        label.numberOfLines = 0
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
        ])
    }
}
