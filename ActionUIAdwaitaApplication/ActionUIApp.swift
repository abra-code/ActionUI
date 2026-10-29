// ActionUIAdwaitaApplication/ActionUIApp.swift
/*
 The actionUIApp* C functions on Linux, over AdwaitaApplication: the same names and signatures as
 ActionUIAppKitApplication's on Apple (prototypes in ActionUIAppKitApplication/include/ActionUIApp.h),
 so one host program (Python, Rust, Node, C) runs on both.

 - Handlers, name, icon and the application ID are set before actionUIAppRun, from the main
   thread. Before the run, a call that must wait for the main thread (the setters, presenting and
   closing windows) is refused from any other thread and logged there: the main thread runs no
   main queue yet, so the call would wait forever. Once the run has begun, any thread may call
   them (the call waits for the main thread). On Apple the setters only store their value.
 - actionUIAppTerminate before the run does nothing; from another thread it waits for the run.
 - actionUIAppRun runs the application on the calling thread, which must be the main thread, and
   returns when it ends. Windows presented before it wait for the start.
 - The alert and the file panels block until the user answers, with the main loop running
   (AppPanels); before the run they log why and return NULL.
 - The remote server (ActionUIRemote) starts from any thread, before the run or during it, and
   stops when the run ends, after the willTerminate handler, as on macOS.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
#if canImport(Glibc)
import Glibc
#endif
import Dispatch
import Synchronization
import ActionUI
import ActionUIAppHeaders
import ActionUIRemote

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
/// runs the main queue (through the GLib loop) and another thread may wait for it.
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

/// The name actionUIAppSetName set, readable from any thread: the remote server answers
/// `actionui.hello` with it, and it may be started from a worker before the run.
private let appName = Mutex<String?>(nil)

// MARK: - Lifecycle handlers

@c
public func actionUIAppSetWillFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willFinishLaunching = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetDidFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.didFinishLaunching = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWillBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willBecomeActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetDidBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.didBecomeActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWillResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willResignActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetDidResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.didResignActive = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWillTerminateHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willTerminate = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetShouldTerminateHandler(_ handler: ActionUIAppShouldTerminateHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.shouldTerminate = handler.map { call in { call() } } }
}

@c
public func actionUIAppSetWindowWillCloseHandler(_ handler: ActionUIAppWindowHandler?) {
    runOnMainActorSync {
        AdwaitaApplication.shared.handlers.windowWillClose = handler.map { call in { uuid in uuid.withCString { call($0) } } }
    }
}

@c
public func actionUIAppSetWindowWillPresentHandler(_ handler: ActionUIAppWindowHandler?) {
    runOnMainActorSync {
        AdwaitaApplication.shared.handlers.windowWillPresent = handler.map { call in { uuid in uuid.withCString { call($0) } } }
    }
}

// MARK: - The application

/// The application's name: window titles default to it, and so does its application ID.
@c
public func actionUIAppSetName(_ name: UnsafePointer<CChar>) {
    let swiftName = String(cString: name)
    runOnMainActorSync {
        // In here, so a refused call (from a worker before the run) leaves the name unchanged.
        appName.withLock { $0 = swiftName }
        AdwaitaApplication.shared.name = swiftName
    }
}

/// The reverse-DNS application ID ("org.example.App"); without one it is made from the name.
@c
public func actionUIAppSetApplicationID(_ applicationID: UnsafePointer<CChar>) {
    let swiftID = String(cString: applicationID)
    runOnMainActorSync { AdwaitaApplication.shared.applicationID = swiftID }
}

/// The windows' icon: the path of a PNG or SVG file, or an icon theme name.
@c
public func actionUIAppSetIcon(_ path: UnsafePointer<CChar>) {
    let swiftPath = String(cString: path)
    runOnMainActorSync { AdwaitaApplication.shared.icon = swiftPath }
}

/// The folder of the app's resources, where LoadableView names and image resources are found (by
/// default the running program's folder, its bundle). An interpreted host, whose program is the
/// interpreter, passes its script's folder; NULL: back to the program's folder.
@c
public func actionUIAppSetResourceFolder(_ path: UnsafePointer<CChar>?) {
    let swiftPath = path.map { String(cString: $0) }
    runOnMainActorSync { AdwaitaApplication.shared.resourceFolder = swiftPath }
}

/// Runs the application until it ends. Must be called from the main thread; from another
/// thread it is refused and logged.
@c
public func actionUIAppRun() {
    guard isMainThread else {
        // Printed here, not queued for the main thread's logger: the main thread is not running
        // the application, so nothing may ever run the main queue to show it.
        ConsoleLogger(maxLevel: .error).log("actionUIAppRun must be called from the main thread; refused", .error)
        return
    }
    // A run from a handler while the application runs is refused by run(); it must not clear
    // the flag of the run still going on.
    let alreadyRunning = applicationRuns.exchange(true, ordering: .acquiringAndReleasing)
    MainActor.assumeIsolated {
        _ = AdwaitaApplication.shared.run()
    }
    if !alreadyRunning {
        applicationRuns.store(false, ordering: .releasing)
        // After the willTerminate handler (in the run), so it could still use the bridge; the
        // socket file would otherwise outlive a host that exits without stopping the server. The
        // C function, not ActionUIRemoteServer.stopShared(): it also forgets the endpoint and
        // token it hands out, which a host that goes on after the run would otherwise still read.
        actionUIRemoteStopServer()
    }
}

/// Ends the application, unless the shouldTerminate handler says no.
@c
public func actionUIAppTerminate() {
    runOnMainActorAsync { AdwaitaApplication.shared.terminate() }
}

/// Adds the CommandMenu and CommandGroup elements in `jsonString` (a JSON array; NULL: none) to
/// the application's commands, which Linux shows in each window's primary menu (GNOME has no menu
/// bar), their shortcuts working in every window.
@c
public func actionUIAppLoadMenuBar(_ jsonString: UnsafePointer<CChar>?) {
    let json = jsonString.map { String(cString: $0) }
    runOnMainActorSync { AdwaitaApplication.shared.loadMenuBar(json: json) }
}

// MARK: - Windows

/// Loads the ActionUI document at `urlString` (a file URL or path, or an http or https URL, whose
/// window appears once it has loaded) into a new window. `title` NULL: the file's name.
@c
public func actionUIAppLoadAndPresentWindow(_ urlString: UnsafePointer<CChar>,
                                            _ windowUUID: UnsafePointer<CChar>,
                                            _ title: UnsafePointer<CChar>?) {
    let swiftURL = String(cString: urlString)
    let swiftUUID = String(cString: windowUUID)
    let swiftTitle = title.map { String(cString: $0) }
    runOnMainActorSync {
        AdwaitaApplication.shared.presentWindow(url: swiftURL, windowUUID: swiftUUID, title: swiftTitle)
    }
}

/// Loads the ActionUI document in `jsonString` into a new window. `title` NULL: the
/// application's name.
@c
public func actionUIAppLoadAndPresentWindowFromJSON(_ jsonString: UnsafePointer<CChar>,
                                                    _ windowUUID: UnsafePointer<CChar>,
                                                    _ title: UnsafePointer<CChar>?) {
    let data = Data(String(cString: jsonString).utf8)
    let swiftUUID = String(cString: windowUUID)
    let swiftTitle = title.map { String(cString: $0) }
    runOnMainActorSync {
        AdwaitaApplication.shared.presentWindow(json: data, windowUUID: swiftUUID, title: swiftTitle)
    }
}

/// Closes the window showing `windowUUID`; the windowWillClose handler fires.
@c
public func actionUIAppCloseWindow(_ windowUUID: UnsafePointer<CChar>) {
    let swiftUUID = String(cString: windowUUID)
    runOnMainActorAsync { AdwaitaApplication.shared.closeWindow(swiftUUID) }
}

// MARK: - Alerts and file panels

/// The title of the button chosen in a standalone alert, configured by the macOS JSON (title,
/// message, style, buttons); nil when there is no answer. Blocks until the user answers, with the
/// main loop running (AppPanels).
@c
public func actionUIAppRunAlert(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = configJSON.map { String(cString: $0) }
    var chosen: String?
    runOnMainActorSync { chosen = AppPanels.runAlert(json: json) }
    return chosen.map { strdup($0) }
}

/// A JSON array of the chosen paths, or nil when the panel was canceled.
@c
public func actionUIAppRunOpenPanel(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = configJSON.map { String(cString: $0) }
    var chosen: [String]?
    runOnMainActorSync { chosen = AppPanels.runOpenPanel(json: json) }
    guard let chosen, let paths = try? ActionUIJSON.string(from: chosen) else { return nil }
    return strdup(paths)
}

/// The chosen path, or nil when the panel was canceled.
@c
public func actionUIAppRunSavePanel(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    let json = configJSON.map { String(cString: $0) }
    var chosen: String?
    runOnMainActorSync { chosen = AppPanels.runSavePanel(json: json) }
    return chosen.map { strdup($0) }
}

// MARK: - The remote server

/// Starts the remote server on `socketPath`, or on a per-process default when it is NULL
/// (in `$XDG_RUNTIME_DIR`, else `$TMPDIR`, else `/tmp`), and exports `ACTIONUI_REMOTE_ENDPOINT`
/// and `ACTIONUI_REMOTE_TOKEN` for the processes started afterwards. `actionui.hello` answers with
/// the name set with actionUIAppSetName. Safe from any thread; false when a server is already
/// running or the socket could not be made (logged).
@c
public func actionUIAppStartRemoteServer(_ socketPath: UnsafePointer<CChar>?) -> CBool {
    guard let name = appName.withLock({ $0 }) else {
        return actionUIRemoteStartServer(socketPath, nil, nil)
    }
    return name.withCString { actionUIRemoteStartServer(socketPath, $0, nil) }
}

/// Stops the server, removes its socket and unsets `ACTIONUI_REMOTE_ENDPOINT`.
@c
public func actionUIAppStopRemoteServer() {
    actionUIRemoteStopServer()
}

/// The token the running server requires, or NULL when it requires none; owned by the library
/// and valid until the next start or stop.
@c
public func actionUIAppRemoteServerToken() -> UnsafePointer<CChar>? {
    return actionUIRemoteServerToken()
}

/// The same token, copied into the caller's buffer under the library's lock: what a host with
/// more than one thread should use (a concurrent stop frees the buffer the pointer form returns).
@c
public func actionUIAppRemoteCopyServerToken(_ outToken: UnsafeMutablePointer<CChar>?, _ outTokenSize: Int) -> CBool {
    return actionUIRemoteCopyServerToken(outToken, outTokenSize)
}

/// The socket path of the running server, or NULL when none is running; owned by the library and
/// valid until the next start or stop.
@c
public func actionUIAppRemoteServerEndpoint() -> UnsafePointer<CChar>? {
    return actionUIRemoteServerEndpoint()
}
