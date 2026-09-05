// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIAppRemoteServer.swift
//  ActionUIAppKitApplication
//
//  The remote bridge under the names the Python and Node bindings use. The lifecycle, the C
//  face, and the endpoint buffer all live in ActionUIRemote (actionUIRemoteStartServer and
//  friends), which is the target a host links for this and the only one OMC takes. All this
//  layer adds is the application name, which only it knows.
//
//  Bool: all @_cdecl functions use Swift's CBool (= stdbool.h bool).
//

import AppKit
import Foundation
import ActionUI
import ActionUIRemote

/// Start the remote server on `socketPath`, or on a per-process default when it is NULL.
///
/// Equivalent to `actionUIRemoteStartServer(socketPath, appName, NULL)`: the only thing added is
/// the name set with `actionUIAppSetName`, so `actionui.hello` answers with the application's
/// name rather than the host process's. See `actionUIRemoteStartServer` for everything else.
@_cdecl("actionUIAppStartRemoteServer")
public func actionUIAppStartRemoteServer(_ socketPath: UnsafePointer<CChar>?) -> CBool {
    guard let name = appName else {
        return actionUIRemoteStartServer(socketPath, nil, nil)
    }
    return name.withCString { actionUIRemoteStartServer(socketPath, $0, nil) }
}

/// Stop the server, remove its socket, and unset `ACTIONUI_REMOTE_ENDPOINT`.
/// Equivalent to `actionUIRemoteStopServer()`.
@_cdecl("actionUIAppStopRemoteServer")
public func actionUIAppStopRemoteServer() {
    actionUIRemoteStopServer()
}

/// The token the running server requires, or NULL when it requires none.
/// Equivalent to `actionUIRemoteServerToken()`, including its lifetime.
@_cdecl("actionUIAppRemoteServerToken")
public func actionUIAppRemoteServerToken() -> UnsafePointer<CChar>? {
    return actionUIRemoteServerToken()
}

/// The same token, copied into the caller's buffer under the framework's lock.
/// Equivalent to `actionUIRemoteCopyServerToken`, and what a host with more than one thread
/// should use: see that function for why the pointer form is not safe against a concurrent stop.
@_cdecl("actionUIAppRemoteCopyServerToken")
public func actionUIAppRemoteCopyServerToken(_ outToken: UnsafeMutablePointer<CChar>?,
                                             _ outTokenSize: Int) -> CBool {
    return actionUIRemoteCopyServerToken(outToken, outTokenSize)
}

/// The socket path of the running server, or NULL when none is running.
/// Equivalent to `actionUIRemoteServerEndpoint()`, including its lifetime: the string is owned
/// by the framework and stays valid until the next start or stop.
@_cdecl("actionUIAppRemoteServerEndpoint")
public func actionUIAppRemoteServerEndpoint() -> UnsafePointer<CChar>? {
    return actionUIRemoteServerEndpoint()
}
