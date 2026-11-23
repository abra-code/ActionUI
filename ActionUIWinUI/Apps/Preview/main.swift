// ActionUIWinUI/Apps/Preview/main.swift - ActionUIWinUIPreview: the preview tool (Apps/PreviewSupport, whose
// Preview.swift lists its options) with the add-on probe (AddOnProbe.swift), for Documents/AddOns.json. Built and
// run by Scripts/ci-windows.py winui on every document in Documents.

import ActionUI
import ActionUIWinUIPreviewSupport

runActionUIWinUIPreview {
    // An element registered the way an add-on registers one.
    ActionUIRegistry.shared.register(AddOnProbe.self, as: "AddOnProbe")
}
