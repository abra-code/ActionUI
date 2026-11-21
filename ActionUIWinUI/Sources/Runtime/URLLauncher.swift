// Sources/Runtime/URLLauncher.swift
/*
 Opens an address with the system (the user's browser, or the app registered for its scheme), for
 the renderer's links once the trust policy allows them. A test tool replaces `launch` to record
 what would open without opening it.
*/

import CWinUI

@MainActor
package enum URLLauncher {
    /// Opens `url` (an absolute URL); false, with the shim's error, when Windows cannot read it as one
    /// or it is a file: or res: link (actionUIWinUILaunchURL).
    package static var launch: @MainActor (String) -> Bool = { url in actionUIWinUILaunchURL(url) }
}
