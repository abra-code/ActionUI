// ActionUILibraryTests/PythonHostTests.swift
/*
 Programs in another language, run as the programs they are, against the built library: Python loads libActionUI.so
 with ctypes and calls its C functions. Build the package first (swift build): this target does not link the library,
 which a Swift test program must not load. They need a display, and skip themselves without one.
*/

import XCTest
import Foundation

final class PythonHostTests: XCTestCase {
    /// The built library, next to the test program.
    private var library: String {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("libActionUI.so").path
    }

    /// A file of these tests.
    private func hostPath(_ name: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Hosts").appendingPathComponent(name).path
    }

    /// A path from the repository's root, found from this file.
    private func repositoryPath(_ relative: String) -> String {
        var folder = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            folder = folder.deletingLastPathComponent()
        }
        return folder.appendingPathComponent(relative).path
    }

    /// What a Python program printed; fails the test if it does not end, or ends in failure.
    private func runPython(_ arguments: [String]) throws -> String? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WAYLAND_DISPLAY"] != nil || environment["DISPLAY"] != nil else {
            throw XCTSkip("no display")
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("no /usr/bin/python3 to host the sample")
        }
        guard FileManager.default.fileExists(atPath: library) else {
            XCTFail("no library at \(library): build the package first")
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if process.isRunning {
            process.terminate()
            XCTFail("the Python host did not end within 60 s")
            return nil
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        return text
    }

    func testThePythonHostConvertsTemperaturesThroughTheCFunctions() throws {
        guard let text = try runPython([hostPath("temperature_converter.py"), library,
                                        repositoryPath("Examples/TemperatureConverter/shared/TemperatureConverter.json"), "--check"]) else {
            return
        }
        for line in ["100 C = 212.00 F (ok)", "37 C = 98.60 F (ok)", "-40 C = -40.00 F (ok)", "212 F = 373.15 K (ok)",
                     "4 of 4 conversions as expected"] {
            XCTAssertTrue(text.contains(line), "missing \"\(line)\" in:\n\(text)")
        }
    }

    // A program in another language has no register() to call: the library registers its add-ons itself.
    func testTheLibrarysAddOnsAreThereForAProgramInAnotherLanguage() throws {
        guard let text = try runPython([hostPath("add_ons.py"), library, hostPath("add_ons.json")]) else {
            return
        }
        XCTAssertTrue(text.contains("add-ons registered"), text)
    }
}
