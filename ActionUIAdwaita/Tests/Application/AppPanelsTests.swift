// Tests/Application/AppPanelsTests.swift
/*
 Tests for the standalone alert and the file panels (AppPanels), behind actionUIAppRunAlert,
 actionUIAppRunOpenPanel and actionUIAppRunSavePanel. The requests: the macOS JSON read key by key
 into libadwaita's and GTK's terms. The panels, in a running application, answered through the test
 hook as the user would: a chosen button, Escape (the close response), no Escape without a cancel
 button, a canceled file panel, an alert whose window goes away, termination with an alert up; one
 called from another thread; a call before the run.
*/

import XCTest
import CAdwaita
import Dispatch
#if canImport(Glibc)
import Glibc
#endif
@testable import ActionUI
import ActionUIAdwaitaApplication

final class AppPanelRequestTests: XCTestCase {
    func testAnAlertShowsItsFirstButtonRightmostAndEscapeAnswersCancel() {
        let request = AlertRequest(json: #"{"title": "Replace Pipeline?", "message": "It will be replaced.", "style": "warning", "buttons": ["Replace", "Cancel"]}"#)
        XCTAssertEqual(request.heading, "Replace Pipeline?")
        XCTAssertEqual(request.body, "It will be replaced.")
        XCTAssertEqual(request.buttons, ["Replace", "Cancel"])
        XCTAssertEqual(request.displayOrder, [1, 0], "added left to right: Cancel, then Replace")
        XCTAssertEqual(request.closeButton, 1)
        XCTAssertEqual(request.button(response: "button-0"), "Replace")
        XCTAssertNil(request.button(response: "close"))
        XCTAssertNil(request.button(response: "button-7"))
    }

    func testAnAlertWithoutButtonsHasOKAndWithoutCancelHasNoEscape() {
        let plain = AlertRequest(json: nil)
        XCTAssertEqual(plain.buttons, ["OK"])
        XCTAssertEqual(plain.closeButton, 0, "a single button answers Escape")
        XCTAssertNil(AlertRequest(json: #"{"buttons": ["Save", "Don't Save"]}"#).closeButton)
        XCTAssertEqual(AlertRequest(json: #"{"title": 3, "buttons": "Yes"}"#), AlertRequest(json: "{}"), "keys of the wrong type are ignored")
    }

    func testAnOpenPanelChoosesFilesOrFolders() {
        XCTAssertEqual(FilePanelRequest(json: nil, saving: false).mode, .openFile)
        XCTAssertEqual(FilePanelRequest(json: #"{"allowsMultipleSelection": true}"#, saving: false).mode, .openFiles)
        XCTAssertEqual(FilePanelRequest(json: #"{"canChooseDirectories": true, "canChooseFiles": false}"#, saving: false).mode, .selectFolder)
        XCTAssertEqual(FilePanelRequest(json: #"{"canChooseDirectories": true, "canChooseFiles": false, "allowsMultipleSelection": true}"#, saving: false).mode, .selectFolders)
        XCTAssertEqual(FilePanelRequest(json: #"{"canChooseDirectories": true}"#, saving: false).mode, .openFile, "files and folders: files")
        XCTAssertEqual(FilePanelRequest(json: #"{"canChooseDirectories": true}"#, saving: true).mode, .save)
    }

    func testThePanelKeysMapToGtkFileDialog() {
        let request = FilePanelRequest(json: #"{"title": "Open Image", "prompt": "Open", "directoryURL": "file:///tmp/My%20Folder", "nameFieldStringValue": "x.png", "allowedContentTypes": ["public.image", "py", "text/csv", "com.example.unknown"]}"#, saving: false)
        XCTAssertEqual(request.title, "Open Image")
        XCTAssertEqual(request.acceptLabel, "Open")
        XCTAssertEqual(request.initialFolder, "/tmp/My Folder")
        XCTAssertNil(request.initialName, "an open panel proposes no name")
        XCTAssertEqual(request.types, [.mimeType("image/*"), .suffix("py"), .mimeType("text/csv")])
        XCTAssertTrue(request.restrictsTypes)
        XCTAssertEqual(FilePanelRequest(json: #"{"directoryURL": "/home/me"}"#, saving: false).initialFolder, "/home/me")
        XCTAssertFalse(FilePanelRequest(json: #"{"allowedContentTypes": ["public.data"]}"#, saving: false).restrictsTypes, "any data is any file")
        XCTAssertFalse(FilePanelRequest(json: nil, saving: false).restrictsTypes)
    }

    func testASavedNameGetsTheFirstAllowedExtension() {
        let request = FilePanelRequest(json: #"{"nameFieldStringValue": "output.png", "allowedContentTypes": ["png", "jpg"]}"#, saving: true)
        XCTAssertEqual(request.initialName, "output.png")
        XCTAssertEqual(request.savedPath("/tmp/picture"), "/tmp/picture.png")
        XCTAssertEqual(request.savedPath("/tmp/picture.JPG"), "/tmp/picture.JPG")
        XCTAssertEqual(request.savedPath("/tmp/v1.2/picture.png"), "/tmp/v1.2/picture.png")
        let others = FilePanelRequest(json: #"{"allowedContentTypes": ["png"], "allowsOtherFileTypes": true}"#, saving: true)
        XCTAssertEqual(others.savedPath("/tmp/notes.txt"), "/tmp/notes.txt", "other types allowed: as typed")
        XCTAssertEqual(FilePanelRequest(json: #"{"allowedContentTypes": ["public.image"]}"#, saving: true).savedPath("/tmp/a"), "/tmp/a", "no extension to add")
    }
}

/// Emits AdwAlertDialog's "response" with `response`, as a click on that button does. (Swift cannot
/// call the variadic g_signal_emit_by_name.)
@MainActor
private func emitResponse(_ response: String, on alert: OpaquePointer) {
    let instance = UnsafeMutableRawPointer(alert)
    let type = instance.assumingMemoryBound(to: GTypeInstance.self).pointee.g_class.pointee.g_type
    let id = g_signal_lookup("response", type)
    precondition(id != 0, "response is not a signal of this object")
    var values = [GValue(), GValue()]
    g_value_init(&values[0], type)
    g_value_set_object(&values[0], instance)
    g_value_init(&values[1], g_type_from_name("gchararray"))
    g_value_set_string(&values[1], response)
    g_signal_emitv(&values, id, 0, nil)
    g_value_unset(&values[0])
    g_value_unset(&values[1])
}

/// What the tests record from inside the run.
nonisolated(unsafe) private var answers: [String] = []

@MainActor
final class AppPanelTests: XCTestCase {
    override func setUp() async throws {
        try AdwaitaTestHost.initialize()
        ActionUIRegistry.shared.loadBuiltIns()
        answers = []
    }

    override func tearDown() async throws {
        AppPanels.presentedForTesting = nil
        actionUIAppSetDidFinishLaunchingHandler(nil)
        ActionUIModel.shared.windowModels["panel-w1"] = nil
        AdwaitaTestHost.drainMainLoop()
    }

    /// Presents a window, runs `body` once the application has launched, then ends the run.
    private func runApplication(_ body: @escaping @convention(c) () -> Void) {
        actionUIAppSetDidFinishLaunchingHandler(body)
        actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "Panels"}}"#, "panel-w1", nil)
        actionUIAppRun()
    }

    /// Answers each dialog `after` milliseconds after it appears, with `answer`.
    private static func answerEach(after milliseconds: UInt32 = 200, _ answer: @escaping @MainActor (OpaquePointer, UnsafeMutablePointer<GCancellable>) -> Void) {
        AppPanels.presentedForTesting = { dialog, cancellable in
            _ = runAfter(milliseconds: milliseconds) { answer(dialog, cancellable) }
        }
    }

    /// Keeps a C call's answer and frees it (strdup'd, as actionUIFreeString frees it).
    nonisolated private static func record(_ answer: UnsafeMutablePointer<CChar>?) {
        answers.append(answer.map { String(cString: $0) } ?? "nil")
        free(answer)
    }

    func testAnAlertReturnsTheChosenButtonAndEscapeTheCancelButton() {
        var responses = ["button-0", "escape", "escape-refused"]
        Self.answerEach { dialog, cancellable in
            switch responses.removeFirst() {
            case "button-0":
                emitResponse("button-0", on: dialog)
            case "escape":
                adw_dialog_close(typed(dialog))
            default:
                // No cancel button: closing does nothing, so the test cancels the call.
                adw_dialog_close(typed(dialog))
                _ = runAfter(milliseconds: 200) { g_cancellable_cancel(cancellable) }
            }
        }
        runApplication {
            AppPanelTests.record(actionUIAppRunAlert(#"{"title": "Replace?", "buttons": ["Replace", "Cancel"]}"#))
            AppPanelTests.record(actionUIAppRunAlert(#"{"title": "Replace?", "buttons": ["Replace", "Cancel"]}"#))
            AppPanelTests.record(actionUIAppRunAlert(#"{"title": "Save?", "buttons": ["Save", "Don't Save"]}"#))
            actionUIAppCloseWindow("panel-w1")
            actionUIAppTerminate()
        }
        XCTAssertEqual(answers, ["Replace", "Cancel", "nil"])
    }

    func testACanceledFilePanelAnswersNothingAndTheLoopRunsMeanwhile() {
        var ticks = 0
        AppPanels.presentedForTesting = { _, cancellable in
            _ = runAfter(milliseconds: 50) { ticks += 1 }
            _ = runAfter(milliseconds: 300) { g_cancellable_cancel(cancellable) }
        }
        runApplication {
            AppPanelTests.record(actionUIAppRunOpenPanel(#"{"title": "Open Image", "allowedContentTypes": ["public.image"], "directoryURL": "/tmp"}"#))
            AppPanelTests.record(actionUIAppRunOpenPanel(#"{"canChooseDirectories": true, "canChooseFiles": false, "allowsMultipleSelection": true}"#))
            AppPanelTests.record(actionUIAppRunSavePanel(#"{"nameFieldStringValue": "output.png", "allowedContentTypes": ["png"], "allowsOtherFileTypes": true}"#))
            actionUIAppCloseWindow("panel-w1")
            actionUIAppTerminate()
        }
        XCTAssertEqual(answers, ["nil", "nil", "nil"])
        XCTAssertEqual(ticks, 3, "a timer fired while each panel was up")
    }

    func testAnAlertWhoseWindowIsReplacedAnswersNothing() {
        AppPanels.presentedForTesting = { _, cancellable in
            // Presenting under the same UUID destroys the alert's window.
            _ = runAfter(milliseconds: 200) {
                actionUIAppLoadAndPresentWindowFromJSON(#"{"type": "Text", "id": 1, "properties": {"text": "Again"}}"#, "panel-w1", nil)
            }
            // Should it never answer, the test fails instead of waiting forever.
            g_object_ref(UnsafeMutableRawPointer(cancellable))
            _ = runAfter(milliseconds: 3000) {
                if g_cancellable_is_cancelled(cancellable) == 0 {
                    answers.append("unanswered")
                    g_cancellable_cancel(cancellable)
                }
                g_object_unref(UnsafeMutableRawPointer(cancellable))
            }
        }
        runApplication {
            AppPanelTests.record(actionUIAppRunAlert(#"{"title": "Replace?", "buttons": ["Replace", "Cancel"]}"#))
            actionUIAppCloseWindow("panel-w1")
            actionUIAppTerminate()
        }
        XCTAssertEqual(answers, ["nil"])
    }

    func testTerminatingWithAPanelUpEndsTheRun() {
        AppPanels.presentedForTesting = { _, cancellable in
            _ = runAfter(milliseconds: 200) { actionUIAppTerminate() }
            // Should it never answer, the test fails instead of waiting forever.
            g_object_ref(UnsafeMutableRawPointer(cancellable))
            _ = runAfter(milliseconds: 3000) {
                if g_cancellable_is_cancelled(cancellable) == 0 {
                    answers.append("unanswered")
                    g_cancellable_cancel(cancellable)
                }
                g_object_unref(UnsafeMutableRawPointer(cancellable))
            }
        }
        runApplication {
            // No cancel button: only the termination can end it.
            AppPanelTests.record(actionUIAppRunAlert(#"{"title": "Save?", "buttons": ["Save", "Don't Save"]}"#))
        }
        XCTAssertEqual(answers, ["nil"], "the alert answered nothing and the run ended")
    }

    func testAnAlertCalledFromAnotherThreadWaitsForItsAnswer() {
        Self.answerEach { dialog, _ in emitResponse("button-0", on: dialog) }
        runApplication {
            DispatchQueue.global().async {
                AppPanelTests.record(actionUIAppRunAlert(#"{"title": "From a worker", "buttons": ["Go", "Cancel"]}"#))
                actionUIAppCloseWindow("panel-w1")
                actionUIAppTerminate()
            }
        }
        XCTAssertEqual(answers, ["Go"])
    }

    func testThePanelsBeforeTheRunAnswerNothing() {
        XCTAssertNil(actionUIAppRunAlert(nil))
        XCTAssertNil(actionUIAppRunOpenPanel(nil))
        XCTAssertNil(actionUIAppRunSavePanel(nil))
    }
}
