// Tests/Views/AsyncImageTests.swift
import XCTest
import SwiftUI
import ImageIO
import UniformTypeIdentifiers
@testable import ActionUI
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class AsyncImageTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!
    
    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIModel.shared.logger = logger
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        windowUUID = UUID().uuidString
    }
    
    override func tearDown() async throws {
        ActionUIRegistry.shared.resetForTesting()
        ActionUIModel.resetForTesting()
        logger = nil
        windowUUID = nil
        try await super.tearDown()
    }
    
    func testAsyncImagePropsValid() throws {
        let properties: [String: Any] = [
            "url": "https://example.com/image.jpg",
            "placeholder": "photo.fill",
            "resizable": true,
            "contentMode": "fit"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertEqual(props.url, "https://example.com/image.jpg", "url should be valid String")
        XCTAssertEqual(props.placeholder, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(props.resizable, true, "resizable should be valid Bool")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be valid")
    }
    
    func testAsyncImagePropsIgnoreInvalid() throws {
        let properties: [String: Any] = [
            "url": 123,
            "placeholder": 456,
            "resizable": "true",
            "contentMode": "invalid"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertNil(props.url, "url should be nil for invalid type")
        XCTAssertEqual(props.placeholder, "photo", "placeholder should be the default for invalid type")
        XCTAssertEqual(props.resizable, true, "resizable should be the default for invalid type")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be the default for invalid value")
    }
    
    func testAsyncImagePropsMissing() throws {
        let properties: [String: Any] = [:]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertNil(props.url, "url should be nil when no properties provided")
        XCTAssertEqual(props.placeholder, "photo", "placeholder should be the default when no properties provided")
        XCTAssertEqual(props.resizable, true, "resizable should be the default when no properties provided")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be the default when no properties provided")
    }
    
    func testAsyncImagePropsPartial() throws {
        let properties: [String: Any] = [
            "url": "https://example.com/image.jpg",
            "placeholder": "photo.fill"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertEqual(props.url, "https://example.com/image.jpg", "url should be valid String")
        XCTAssertEqual(props.placeholder, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(props.resizable, true, "resizable should be the default when not provided")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be the default when not provided")
    }
    
    func testAsyncImagePropsInvalidUrl() throws {
        let properties: [String: Any] = [
            "url": "invalid-url",
            "placeholder": "photo.fill",
            "resizable": true,
            "contentMode": "fit"
        ]
        
        let props = AsyncImage.Props(properties)
        
        XCTAssertEqual(props.url, "invalid-url", "url should pass through as string, even if invalid")
        XCTAssertEqual(props.placeholder, "photo.fill", "placeholder should be valid String")
        XCTAssertEqual(props.resizable, true, "resizable should be valid Bool")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be valid")
    }
    
    func testBuildViewAndApplyModifiersValidUrl() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "AsyncImage",
            "properties": [
                "url": "https://example.com/image.jpg",
                "placeholder": "photo.fill",
                "resizable": true,
                "contentMode": "fit"
            ]
        ]
        
        let actionUIModel = ActionUIModel.shared
        let element = try actionUIModel.loadDescription(from: elementDict, windowUUID: windowUUID)
        guard let windowModel = actionUIModel.windowModels[windowUUID],
              let viewModel = windowModel.viewModels[element.id] else {
            XCTFail("Failed to retrieve viewModel")
            return
        }

        // Act: Create ActionUIView
        let actionUIView = ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
        let _ = actionUIView.body // Access the body to trigger view construction

        // Note: Avoid strict type checks (e.g., SwiftUI.AsyncImage<AnyView>) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers (e.g., padding), wrapping the view in _ModifiedContent
        // Note: Cannot inspect AsyncImage phase or modifiers due to SwiftUI's opaque hierarchy and async nature
    }
    
    func testBuildViewAndApplyModifiersInvalidUrl() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "AsyncImage",
            "properties": [
                "url": "invalid-url",
                "placeholder": "photo.fill",
                "resizable": true,
                "contentMode": "fit"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = AsyncImage.buildView(element, viewModel, windowUUID, properties, logger)
        _ = AsyncImage.applyModifiers(view, element, windowUUID, properties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Image) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
    
    func testBuildViewAndApplyModifiersMissingUrl() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "AsyncImage",
            "properties": [
                "placeholder": "photo.fill",
                "resizable": true,
                "contentMode": "fit"
            ]
        ]

        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = AsyncImage.buildView(element, viewModel, windowUUID, properties, logger)
        _ = AsyncImage.applyModifiers(view, element, windowUUID, properties, logger)
        // Note: Avoid strict type checks (e.g., SwiftUI.Image) due to SwiftUI's opaque type system
        // Note: ActionUIRegistry.build may apply baseline modifiers, wrapping the view in _ModifiedContent
        // Note: Cannot inspect modifiers due to SwiftUI's opaque hierarchy
    }
}

// A file: URL ActionUI JSON names could be a device or a named pipe; URLSession would read /dev/zero
// until memory runs out, or hold a thread on a pipe for good. Only a regular file is loaded.
extension AsyncImageTests {
    func testAFileURLThatIsNotARegularFileIsNotLoaded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("async-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("a.png")
        try Data([0]).write(to: file)
        let pipe = folder.appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)

        XCTAssertTrue(AsyncImage.isLoadable(URL(string: "https://example.com/a.png")!))
        XCTAssertTrue(AsyncImage.isLoadable(file))
        for url in [URL(string: "file:///dev/zero")!, pipe, folder, folder.appendingPathComponent("missing.png")] {
            XCTAssertFalse(AsyncImage.isLoadable(url), url.path)
        }
    }

    // MARK: - Less-trusted content's images (PrivateAsyncImage)

    /// A `width` x `height` image encoded as `type`, with an EXIF orientation when given.
    private func encodedImage(width: Int, height: Int, type: UTType = .png, orientation: Int? = nil) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: 0.1, green: 0.5, blue: 0.9, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        let properties: [CFString: Any] = orientation.map { [kCGImagePropertyOrientation: $0] } ?? [:]
        CGImageDestinationAddImage(destination, context.makeImage()!, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func testAnImageIsDecodedWithItsOrientation() throws {
        let plain = try PrivateImageLoad.decode(encodedImage(width: 30, height: 20))
        XCTAssertEqual([plain.width, plain.height], [30, 20])
        // Orientation 6: stored landscape, shown turned a quarter turn, so portrait.
        let turned = try PrivateImageLoad.decode(encodedImage(width: 30, height: 20, type: .jpeg, orientation: 6))
        XCTAssertEqual([turned.width, turned.height], [20, 30])
        XCTAssertThrowsError(try PrivateImageLoad.decode(Data("not an image".utf8)))
    }

    func testAnImageOverThePixelOrByteLimitIsRefused() throws {
        let savedPixels = ImageSource.maximumPixelCount
        defer { ImageSource.maximumPixelCount = savedPixels }
        ImageSource.maximumPixelCount = 100
        XCTAssertThrowsError(try PrivateImageLoad.decode(encodedImage(width: 11, height: 10)), "declares 110 pixels")
        XCTAssertNoThrow(try PrivateImageLoad.decode(encodedImage(width: 10, height: 10)))

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("private-image-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("picture.png")
        let bytes = encodedImage(width: 10, height: 10)
        try bytes.write(to: file)
        let savedBytes = PrivateImageLoad.maximumBytes
        defer { PrivateImageLoad.maximumBytes = savedBytes }
        PrivateImageLoad.maximumBytes = bytes.count
        XCTAssertEqual(try PrivateImageLoad.readFile(file), bytes)
        PrivateImageLoad.maximumBytes = bytes.count - 1
        XCTAssertThrowsError(try PrivateImageLoad.readFile(file), "one byte over")
        XCTAssertThrowsError(try PrivateImageLoad.readFile(URL(fileURLWithPath: "/dev/zero")), "a device")
    }

    func testARemoteImageIsFetchedWithThePrivateSession() async throws {
        let address = "data:image/png;base64," + encodedImage(width: 12, height: 8).base64EncodedString()
        let image = try await PrivateImageLoad.load(try XCTUnwrap(URL(string: address)))
        XCTAssertEqual([image.width, image.height], [12, 8])
    }

    #if os(macOS)
    /// Keeps every message, so a test can see which loader showed an image.
    private final class CapturingLogger: ActionUILogger, @unchecked Sendable {
        var messages: [String] = []
        func log(_ message: String, _ level: LoggerLevel) { messages.append(message) }
    }

    /// Less-trusted content's AsyncImage goes through PrivateAsyncImage (which logs an image it
    /// refuses); trusted content's through SwiftUI's AsyncImage, as before (which logs nothing).
    func testOnlyLessTrustedContentsImageGoesThroughThePrivateLoader() throws {
        let savedPixels = ImageSource.maximumPixelCount
        defer { ImageSource.maximumPixelCount = savedPixels }
        ImageSource.maximumPixelCount = 10
        let capturing = CapturingLogger()
        let savedLogger = ActionUIModel.shared.logger
        ActionUIModel.shared.logger = capturing
        defer { ActionUIModel.shared.logger = savedLogger }
        let address = "data:image/png;base64," + encodedImage(width: 8, height: 8).base64EncodedString()
        let json = #"{"type": "AsyncImage", "id": 1, "properties": {"url": "\#(address)"}}"#
        func show(origin: JSONContentOrigin?) throws {
            windowUUID = UUID().uuidString
            let element = try ActionUIModel.shared.loadDescription(from: Data(json.utf8), format: "json", windowUUID: windowUUID, origin: origin)
            let viewModel = try XCTUnwrap(ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id])
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
            window.contentView = NSHostingView(rootView: ActionUIView(element: element, model: viewModel, windowUUID: windowUUID)
                .frame(width: 200, height: 200))
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            let deadline = Date().addingTimeInterval(3)
            while Date() < deadline, !capturing.messages.contains(where: { $0.hasPrefix("AsyncImage not shown") }) {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            }
        }
        try show(origin: nil)
        XCTAssertFalse(capturing.messages.contains { $0.hasPrefix("AsyncImage not shown") }, "the host's content: SwiftUI's AsyncImage")
        let remote = JSONContentOrigin(source: .remote(URL(string: "https://example.com/v.json")!), trust: .lessTrusted, parentID: nil)
        try show(origin: remote)
        XCTAssertTrue(capturing.messages.contains { $0.hasPrefix("AsyncImage not shown") && $0.contains("8 x 8 pixels") }, "\(capturing.messages)")
    }
    #endif
}
