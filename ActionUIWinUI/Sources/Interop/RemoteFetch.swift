// Sources/Interop/RemoteFetch.swift
/*
 An address's contents fetched without blocking the UI thread (the shim's actionUIWinUIFetchURL:
 Windows' HTTP client, the body read up to a limit, given up after a time, redirects followed only to
 http and https, never from https to http), for the application layer's windows from a server. The
 completion runs on the main actor with the bytes and the address they finally came from (nil: the
 address asked for), or why not.
*/

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import CWinUI

@MainActor package enum RemoteFetch {
    /// What a fetch's completion gets: the bytes and the final address (after redirects, nil without
    /// one), or why not.
    package typealias Completion = @MainActor (_ data: Data?, _ finalURL: String?, _ failure: String?) -> Void

    fileprivate final class Box {
        let completion: Completion

        init(_ completion: @escaping Completion) {
            self.completion = completion
        }
    }

    /// Starts fetching `url` (http or https) with the cap on ActionUI JSON and 120 seconds, as a
    /// LoadableView's download; false (the completion never called) when it could not start, with the
    /// shim's error.
    package static func start(_ url: String, _ completion: @escaping Completion) -> Bool {
        let context = Unmanaged.passRetained(Box(completion)).toOpaque()
        guard actionUIWinUIFetchURL(url, Int64(WindowModel.maximumJSONSize), 120, fetched, context) else {
            // Never called back: the box is let go here.
            Unmanaged<Box>.fromOpaque(context).release()
            return false
        }
        return true
    }
}

private let fetched: ActionUIWinUIDataCompletion = { context, bytes, length, finalURL, error in
    guard let context else { return }
    let data = bytes.map { Data(bytes: $0, count: length) }
    let finalText = finalURL.map { String(cString: $0) }
    let failure = error.map { String(cString: $0) }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        let box = Unmanaged<RemoteFetch.Box>.fromOpaque(pointer).takeRetainedValue()
        box.completion(data, finalText, failure)
    }
}
