import SwiftUI
import Combine
import ActionUI
import ActionUIWebKitJSAdapter

struct WebKitJSContentView: View {
    @StateObject private var viewModel = WebKitJSViewModel()
    
    var body: some View {
        Group {
            if let view = viewModel.swiftUIView {
                AnyView(view)
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
            }
        }
        .frame(minWidth: 300, minHeight: 200)
        .onAppear {
            viewModel.setupJavaScript()
        }
    }
}

@MainActor
class WebKitJSViewModel: ObservableObject {
    @Published var swiftUIView: (any SwiftUI.View)?
    private let adapter = ActionUIWebKitJS(jsSource: .appBundle(fileName: "BusinessLogic"))
    private let windowUUID = "window-12345"
    
    func setupJavaScript() {
        // Load UI description from JSON
        guard let uiURL = Bundle.main.url(forResource: "DefaultWindowContentView", withExtension: "json") else {
            print("Error: Could not find UIDescription.json")
            return
        }
        let view = adapter.loadView(from: uiURL, windowUUID: windowUUID, isContentView: true)
        swiftUIView = view
    }
}
