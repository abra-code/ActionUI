// ActionUIWinUIApplication/ActionUIApp.swift
/*
 The actionUIApp* C functions on Windows, over WinUIApplication: the same names and signatures as
 ActionUIAppKitApplication's on Apple and ActionUIAdwaitaApplication's on Linux (prototypes in
 ActionUIAppKitApplication/include/ActionUIApp.h), so one host program (Python, Rust, Node, C) runs on
 all three. In ActionUI.dll with the C adapter, so both reach the same ActionUI.

 - Handlers, the name, the icon and the resource folder are set before actionUIAppRun, from the main
   thread. Before the run, a call that must wait for the main thread is refused from any other thread
   and logged there: the main thread runs no main queue yet, so the call would wait forever. Once the
   run has begun, any thread may call them (the call waits for the main thread). As on Linux.
 - actionUIAppRun runs the application on the calling thread, which must be the main thread, and
   returns when it ends. Windows presented before it wait for the start.
 - actionUIAppSetApplicationID does nothing on Windows (an unpackaged program has no identity to set).

 - actionUIAppRunAlert, actionUIAppRunOpenPanel and actionUIAppRunSavePanel wait for the user's answer,
   the application running underneath (AppPanels).

 Not yet on Windows (logged; NULL or false): the menu bar and the remote server.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch
import Synchronization
import ucrt
import ActionUI
import ActionUIAppHeaders

// MARK: - Main thread

private let mainQueueKey: DispatchSpecificKey<Bool> = {
    let key = DispatchSpecificKey<Bool>()
    DispatchQueue.main.setSpecific(key: key, value: true)
    return key
}()

private var isMainThread: Bool {
    DispatchQueue.getSpecific(key: mainQueueKey) == true
}

/// True from just before actionUIAppRun runs the application until it returns: then the main thread
/// runs the main queue (MainLoopBridge) and another thread may wait for it.
private let applicationRuns = Atomic<Bool>(false)

/// Runs `operation` on the main actor: at once on the main thread, else queued there.
private func runOnMainActorAsync(_ operation: @escaping @MainActor () -> Void) {
    if isMainThread {
        MainActor.assumeIsolated { operation() }
    } else {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { operation() }
        }
    }
}

/// Runs `operation` on the main actor and waits for it. From another thread before the run it is
/// refused and logged on that thread: nothing runs the main queue yet, so waiting would never end.
private func runOnMainActorSync(_ function: String = #function, _ operation: @MainActor () -> Void) {
    if isMainThread {
        MainActor.assumeIsolated { operation() }
    } else if applicationRuns.load(ordering: .acquiring) {
        DispatchQueue.main.sync {
            MainActor.assumeIsolated { operation() }
        }
    } else {
        ConsoleLogger(maxLevel: .error).log("\(function): refused from a thread other than the main thread before actionUIAppRun", .error)
    }
}

/// Logs that `function` is not available on Windows yet.
private func notYet(_ function: String) {
    runOnMainActorAsync {
        ActionUIModel.shared.logger.log("\(function) is not available on Windows yet", .warning)
    }
}

// MARK: - Lifecycle handlers

@c
public func actionUIAppSetWillFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.willFinishLaunching = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetDidFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.didFinishLaunching = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWillBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.willBecomeActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetDidBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.didBecomeActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWillResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.willResignActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetDidResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.didResignActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWillTerminateHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.willTerminate = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetShouldTerminateHandler(_ handler: ActionUIAppShouldTerminateHandler?) {
    runOnMainActorSync { WinUIApplication.shared.handlers.shouldTerminate = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWindowWillCloseHandler(_ handler: ActionUIAppWindowHandler?) {
    runOnMainActorSync {
        WinUIApplication.shared.handlers.windowWillClose = handler.map { call in { uuid in uuid.withCString { call($0) } } }
    }
}

@c
public func actionUIAppSetWindowWillPresentHandler(_ handler: ActionUIAppWindowHandler?) {
    runOnMainActorSync {
        WinUIApplication.shared.handlers.windowWillPresent = handler.map { call in { uuid in uuid.withCString { call($0) } } }
    }
}

// MARK: - The application

/// The application's name: a window's title when none is given.
@c
public func actionUIAppSetName(_ name: UnsafePointer<CChar>) {
    let swiftName = String(cString: name)
    runOnMainActorSync { WinUIApplication.shared.name = swiftName }
}

/// Nothing on Windows: an unpackaged program has no application identity to set.
@c
public func actionUIAppSetApplicationID(_ applicationID: UnsafePointer<CChar>) {
}

/// The windows' icon: the path of an image file (kept; not shown on Windows yet).
@c
public func actionUIAppSetIcon(_ path: UnsafePointer<CChar>) {
    let swiftPath = String(cString: path)
    runOnMainActorSync { WinUIApplication.shared.icon = swiftPath }
}

/// The folder of the app's resources, whose ActionUI JSON is the app's own (by default the running
/// program's folder). An interpreted host, whose program is the interpreter, passes its script's
/// folder; NULL: back to the program's folder.
@c
public func actionUIAppSetResourceFolder(_ path: UnsafePointer<CChar>?) {
    let swiftPath = path.map { String(cString: $0) }
    runOnMainActorSync { WinUIApplication.shared.resourceFolder = swiftPath }
}

/// Runs the application until it ends. Must be called from the main thread; from another thread it
/// is refused and logged.
@c
public func actionUIAppRun() {
    guard isMainThread else {
        // Printed here, not queued for the main thread's logger: the main thread is not running the
        // application, so nothing may ever run the main queue to show it.
        ConsoleLogger(maxLevel: .error).log("actionUIAppRun must be called from the main thread; refused", .error)
        return
    }
    // A run from a handler while the application runs is refused by run(); it must not clear the flag
    // of the run still going on.
    let alreadyRunning = applicationRuns.exchange(true, ordering: .acquiringAndReleasing)
    MainActor.assumeIsolated {
        _ = WinUIApplication.shared.run()
    }
    if !alreadyRunning {
        applicationRuns.store(false, ordering: .releasing)
    }
}

/// Ends the application, unless the shouldTerminate handler says no.
@c
public func actionUIAppTerminate() {
    runOnMainActorAsync { WinUIApplication.shared.terminate() }
}

/// Not yet on Windows: the menu bar.
@c
public func actionUIAppLoadMenuBar(_ jsonString: UnsafePointer<CChar>?) {
    notYet("actionUIAppLoadMenuBar")
}

// MARK: - Windows

/// Loads the ActionUI JSON at `urlString` (a file URL or a path) into a new window. `title` NULL:
/// the file's name.
@c
public func actionUIAppLoadAndPresentWindow(_ urlString: UnsafePointer<CChar>,
                                            _ windowUUID: UnsafePointer<CChar>,
                                            _ title: UnsafePointer<CChar>?) {
    let swiftURL = String(cString: urlString)
    let swiftUUID = String(cString: windowUUID)
    let swiftTitle = title.map { String(cString: $0) }
    runOnMainActorSync {
        WinUIApplication.shared.presentWindow(url: swiftURL, windowUUID: swiftUUID, title: swiftTitle)
    }
}

/// Loads the ActionUI JSON in `jsonString` into a new window. `title` NULL: the application's
/// name.
@c
public func actionUIAppLoadAndPresentWindowFromJSON(_ jsonString: UnsafePointer<CChar>,
                                                    _ windowUUID: UnsafePointer<CChar>,
                                                    _ title: UnsafePointer<CChar>?) {
    let json = String(cString: jsonString)
    let swiftUUID = String(cString: windowUUID)
    let swiftTitle = title.map { String(cString: $0) }
    runOnMainActorSync {
        WinUIApplication.shared.presentWindow(json: json, windowUUID: swiftUUID, title: swiftTitle)
    }
}

/// Closes the window showing `windowUUID`; the windowWillClose handler fires.
@c
public func actionUIAppCloseWindow(_ windowUUID: UnsafePointer<CChar>) {
    let swiftUUID = String(cString: windowUUID)
    runOnMainActorAsync { WinUIApplication.shared.closeWindow(swiftUUID) }
}

// MARK: - The alert (AppPanels)

/// The chosen button's title, or nil when the alert closed unanswered; the caller frees it with
/// actionUIFreeString.
@c
public func actionUIAppRunAlert(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = configJSON.map { String(cString: $0) }
    var chosen: String?
    runOnMainActorSync { chosen = AppPanels.runAlert(json: json) }
    // The C runtime's strdup (its POSIX name is deprecated): actionUIFreeString frees it.
    return chosen.map { title in title.withCString { _strdup($0) } }
}

// MARK: - File panels (AppPanels)

/// A JSON array of the chosen paths, or nil when the panel was canceled; the caller frees it with
/// actionUIFreeString.
@c
public func actionUIAppRunOpenPanel(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = configJSON.map { String(cString: $0) }
    var chosen: [String]?
    runOnMainActorSync { chosen = AppPanels.runOpenPanel(json: json) }
    guard let chosen, let paths = try? ActionUIJSON.string(from: chosen) else { return nil }
    return paths.withCString { _strdup($0) }
}

/// The chosen path, or nil when the panel was canceled; the caller frees it with actionUIFreeString.
@c
public func actionUIAppRunSavePanel(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = configJSON.map { String(cString: $0) }
    var chosen: String?
    runOnMainActorSync { chosen = AppPanels.runSavePanel(json: json) }
    return chosen.map { path in path.withCString { _strdup($0) } }
}

// MARK: - The remote server (not yet on Windows)

@c
public func actionUIAppStartRemoteServer(_ socketPath: UnsafePointer<CChar>?) -> CBool {
    notYet("actionUIAppStartRemoteServer")
    return false
}

@c
public func actionUIAppStopRemoteServer() {
}

@c
public func actionUIAppRemoteServerToken() -> UnsafePointer<CChar>? {
    return nil
}

@c
public func actionUIAppRemoteCopyServerToken(_ outToken: UnsafeMutablePointer<CChar>?, _ outTokenSize: Int) -> CBool {
    return false
}

@c
public func actionUIAppRemoteEnablePerformAction() -> CBool {
    return false
}

@c
public func actionUIAppRemoteServerEndpoint() -> UnsafePointer<CChar>? {
    return nil
}

/// No server runs, so no token was put in the environment: nothing to remove.
@c
public func actionUIAppRemoteUnexportToken() -> CBool {
    return false
}

/// No server runs, so no token can be minted.
@c
public func actionUIAppRemoteMintToken(_ label: UnsafePointer<CChar>?, _ outToken: UnsafeMutablePointer<CChar>?, _ outTokenSize: Int) -> CBool {
    return false
}

@c
public func actionUIAppRemoteRevokeTokensWithLabel(_ label: UnsafePointer<CChar>?) {
}
