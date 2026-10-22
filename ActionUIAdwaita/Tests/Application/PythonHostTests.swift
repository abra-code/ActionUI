// Tests/Application/PythonHostTests.swift
/*
 The TemperatureConverter sample hosted from Python, run as the program it is: Python loads the
 built libActionUI.so with ctypes, opens the sample through the C functions, sets the inputs,
 converts four temperatures and checks the results (Hosts/temperature_converter.py --check).
*/

import XCTest
import Foundation
@testable import ActionUI

@MainActor
final class PythonHostTests: XCTestCase {
    override func setUp() async throws {
        // No super.setUp(): XCTestCase's does nothing, and on Linux calling it from the main actor
        // sends the non-Sendable test case across actors, which Swift 6 refuses.
        try AdwaitaTestHost.initialize()
    }

    /// The built library, next to the test program.
    private var library: String {
        URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().appendingPathComponent("libActionUI.so").path
    }

    /// A path from the package's root, found from this file.
    private func packagePath(_ relative: String) -> String {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent(relative).path
    }

    func testThePythonHostConvertsTemperaturesThroughTheCFunctions() throws {
        guard FileManager.default.fileExists(atPath: library) else {
            XCTFail("no library at \(library)")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/python3") else {
            throw XCTSkip("no /usr/bin/python3 to host the sample")
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        process.arguments = [packagePath("ActionUIAdwaita/Tests/Hosts/temperature_converter.py"), library,
                             packagePath("Examples/TemperatureConverter/shared/TemperatureConverter.json"), "--check"]
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
            return
        }
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, text)
        for line in ["100 C = 212.00 F (ok)", "37 C = 98.60 F (ok)", "-40 C = -40.00 F (ok)", "212 F = 373.15 K (ok)",
                     "4 of 4 conversions as expected"] {
            XCTAssertTrue(text.contains(line), "missing \"\(line)\" in:\n\(text)")
        }
    }
}
