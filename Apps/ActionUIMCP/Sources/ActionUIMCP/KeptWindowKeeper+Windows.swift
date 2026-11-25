// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

// KeptWindowKeeper+Windows.swift - kept windows on Windows: not yet. WinUIPlatform.keepsWindows is false, so
// 'keep' is refused and no window is handed off; the keeper process and its launcher refuse to run.

#if os(Windows)

import FoundationEssentials

/// Starts the keeper: not on Windows yet.
enum KeeperLauncher {
    enum Outcome {
        case ready(String)
        case notReady(String)
        case failed(String)
    }

    static func launch(executable: String, spool: String, timeout: Double) -> Outcome {
        .failed("kept windows are not available on Windows yet")
    }
}

/// The keeper process: not on Windows yet.
@MainActor
final class KeptWindowKeeper {
    func start(spool: URL, readyFD: Int32?) -> Bool {
        HostSupport.logLine("actionui-mcp: kept windows are not available on Windows yet")
        return false
    }
}

#endif
