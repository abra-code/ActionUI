import SwiftUI

/// Wrapper view that tracks focus state on macOS and fires onSubmit when focus is lost,
/// matching classic AppKit text field behavior where tabbing/clicking away commits the value.
/// On iOS/iPadOS this is a transparent passthrough — focus loss does not trigger submit.
/// Used by both TextField and SecureField.
struct TextFieldFocusContainer<Content: SwiftUI.View>: SwiftUI.View {
    let onSubmit: () -> Void
    let content: () -> Content
    #if os(macOS)
    @FocusState private var isFocused: Bool
    #endif

    init(onSubmit: @escaping () -> Void, @ViewBuilder content: @escaping () -> Content) {
        self.onSubmit = onSubmit
        self.content = content
    }

    var body: some SwiftUI.View {
        #if os(macOS)
        content()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    onSubmit()
                }
            }
        #else
        content()
        #endif
    }
}
