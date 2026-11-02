// ActionUIAdwaita/Apps/Tests/ActionUIAdwaitaAppsTests/ProgramTestSupport.swift
/*
 What the demo's tests need: the program built next to the test program, the repository, and a skip
 when there is no display. The viewer's tests, in Apps/ActionUIViewer, have a copy with more.
*/

import XCTest
import CAdwaita
import Foundation

@MainActor
enum ProgramTestSupport {
    private static var hasDisplay: Bool?

    /// Throws XCTSkip when GTK cannot open a display: the programs cannot show a window then.
    static func requireDisplay() throws {
        if hasDisplay == nil {
            hasDisplay = gtk_init_check() != 0
        }
        if hasDisplay != true {
            throw XCTSkip("GTK could not open a display; the program tests run in the desktop session")
        }
    }

    /// A program of this package, built next to the test program.
    static func program(_ name: String) -> URL {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent(name)
    }

    /// The repository, found from this file.
    static var repository: URL {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            folder = folder.deletingLastPathComponent()
        }
        return folder
    }

    /// Runs `program` with `arguments` for at most 30 s; its exit status, or nil when it had to be stopped.
    static func run(_ program: URL, _ arguments: [String]) throws -> Int32? {
        let process = Process()
        process.executableURL = program
        process.arguments = arguments
        try process.run()
        let deadline = Date().addingTimeInterval(30)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        return process.terminationStatus
    }
}
