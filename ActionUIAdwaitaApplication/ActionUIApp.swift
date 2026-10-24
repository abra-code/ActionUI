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
 - Not on Linux yet, logged at each call: the menu bar (actionUIAppLoadMenuBar does nothing), the
   alert and the file panels (they return NULL, as on an error), the remote server (it does not
   start; the token and endpoint are NULL).
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Dispatch
import Synchronization
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

private func logNotOnLinux(_ what: String) {
    runOnMainActorAsync {
        ActionUIModel.shared.logger.log("\(what) is not available on Linux yet", .warning)
    }
}

// MARK: - Lifecycle handlers

@_cdecl("actionUIAppSetWillFinishLaunchingHandler")
public func actionUIAppSetWillFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willFinishLaunching = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetDidFinishLaunchingHandler")
public func actionUIAppSetDidFinishLaunchingHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.didFinishLaunching = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetWillBecomeActiveHandler")
public func actionUIAppSetWillBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willBecomeActive = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetDidBecomeActiveHandler")
public func actionUIAppSetDidBecomeActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.didBecomeActive = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetWillResignActiveHandler")
public func actionUIAppSetWillResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willResignActive = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetDidResignActiveHandler")
public func actionUIAppSetDidResignActiveHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.didResignActive = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetWillTerminateHandler")
public func actionUIAppSetWillTerminateHandler(_ handler: ActionUIAppLifecycleHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.willTerminate = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetShouldTerminateHandler")
public func actionUIAppSetShouldTerminateHandler(_ handler: ActionUIAppShouldTerminateHandler?) {
    runOnMainActorSync { AdwaitaApplication.shared.handlers.shouldTerminate = handler.map { call in { call() } } }
}

@_cdecl("actionUIAppSetWindowWillCloseHandler")
public func actionUIAppSetWindowWillCloseHandler(_ handler: ActionUIAppWindowHandler?) {
    runOnMainActorSync {
        AdwaitaApplication.shared.handlers.windowWillClose = handler.map { call in { uuid in uuid.withCString { call($0) } } }
    }
}

@_cdecl("actionUIAppSetWindowWillPresentHandler")
public func actionUIAppSetWindowWillPresentHandler(_ handler: ActionUIAppWindowHandler?) {
    runOnMainActorSync {
        AdwaitaApplication.shared.handlers.windowWillPresent = handler.map { call in { uuid in uuid.withCString { call($0) } } }
    }
}

// MARK: - The application

/// The application's name: window titles default to it, and so does its application ID.
@_cdecl("actionUIAppSetName")
public func actionUIAppSetName(_ name: UnsafePointer<CChar>) {
    let swiftName = String(cString: name)
    runOnMainActorSync { AdwaitaApplication.shared.name = swiftName }
}

/// The reverse-DNS application ID ("org.example.App"); without one it is made from the name.
@_cdecl("actionUIAppSetApplicationID")
public func actionUIAppSetApplicationID(_ applicationID: UnsafePointer<CChar>) {
    let swiftID = String(cString: applicationID)
    runOnMainActorSync { AdwaitaApplication.shared.applicationID = swiftID }
}

/// The windows' icon: the path of a PNG or SVG file, or an icon theme name.
@_cdecl("actionUIAppSetIcon")
public func actionUIAppSetIcon(_ path: UnsafePointer<CChar>) {
    let swiftPath = String(cString: path)
    runOnMainActorSync { AdwaitaApplication.shared.icon = swiftPath }
}

/// The folder of the app's resources, where LoadableView names and image resources are found (by
/// default the running program's folder, its bundle). An interpreted host, whose program is the
/// interpreter, passes its script's folder; NULL: back to the program's folder.
@_cdecl("actionUIAppSetResourceFolder")
public func actionUIAppSetResourceFolder(_ path: UnsafePointer<CChar>?) {
    let swiftPath = path.map { String(cString: $0) }
    runOnMainActorSync { AdwaitaApplication.shared.resourceFolder = swiftPath }
}

/// Runs the application until it ends. Must be called from the main thread; from another
/// thread it is refused and logged.
@_cdecl("actionUIAppRun")
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
    }
}

/// Ends the application, unless the shouldTerminate handler says no.
@_cdecl("actionUIAppTerminate")
public func actionUIAppTerminate() {
    runOnMainActorAsync { AdwaitaApplication.shared.terminate() }
}

/// Not on Linux yet: there is no menu bar to load.
@_cdecl("actionUIAppLoadMenuBar")
public func actionUIAppLoadMenuBar(_ jsonString: UnsafePointer<CChar>?) {
    logNotOnLinux("actionUIAppLoadMenuBar (the menu bar)")
}

// MARK: - Windows

/// Loads the ActionUI document at `urlString` (a file URL or path, or an http or https URL, whose
/// window appears once it has loaded) into a new window. `title` NULL: the file's name.
@_cdecl("actionUIAppLoadAndPresentWindow")
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
@_cdecl("actionUIAppLoadAndPresentWindowFromJSON")
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
@_cdecl("actionUIAppCloseWindow")
public func actionUIAppCloseWindow(_ windowUUID: UnsafePointer<CChar>) {
    let swiftUUID = String(cString: windowUUID)
    runOnMainActorAsync { AdwaitaApplication.shared.closeWindow(swiftUUID) }
}

// MARK: - Alerts and file panels (not on Linux yet)

@_cdecl("actionUIAppRunAlert")
public func actionUIAppRunAlert(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    logNotOnLinux("actionUIAppRunAlert")
    return nil
}

@_cdecl("actionUIAppRunOpenPanel")
public func actionUIAppRunOpenPanel(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    logNotOnLinux("actionUIAppRunOpenPanel")
    return nil
}

@_cdecl("actionUIAppRunSavePanel")
public func actionUIAppRunSavePanel(_ configJSON: UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>? {
    logNotOnLinux("actionUIAppRunSavePanel")
    return nil
}

// MARK: - The remote server (not on Linux yet)

@_cdecl("actionUIAppStartRemoteServer")
public func actionUIAppStartRemoteServer(_ socketPath: UnsafePointer<CChar>?) -> CBool {
    logNotOnLinux("The remote server")
    return false
}

@_cdecl("actionUIAppStopRemoteServer")
public func actionUIAppStopRemoteServer() {
}

@_cdecl("actionUIAppRemoteServerToken")
public func actionUIAppRemoteServerToken() -> UnsafePointer<CChar>? {
    nil
}

@_cdecl("actionUIAppRemoteCopyServerToken")
public func actionUIAppRemoteCopyServerToken(_ outToken: UnsafeMutablePointer<CChar>?, _ outTokenSize: Int) -> CBool {
    false
}

@_cdecl("actionUIAppRemoteServerEndpoint")
public func actionUIAppRemoteServerEndpoint() -> UnsafePointer<CChar>? {
    nil
}
