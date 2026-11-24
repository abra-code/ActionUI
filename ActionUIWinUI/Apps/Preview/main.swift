// ActionUIWinUI/Apps/Preview/main.swift - ActionUIWinUIPreview: the preview tool (Apps/PreviewSupport, whose
// Preview.swift lists its options) with the add-on probe (AddOnProbe.swift), for TestFiles/AddOns.json. Built and
// run by Scripts/ci-windows.py winui on every test file in TestFiles.

import ActionUI
import ActionUIWinUIPreviewSupport

runActionUIWinUIPreview {
    // An element registered the way an add-on registers one.
    ActionUIRegistry.shared.register(AddOnProbe.self, as: "AddOnProbe")
}
