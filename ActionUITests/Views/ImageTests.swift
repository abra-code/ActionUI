// Tests/Views/ImageTests.swift
/*
 ImageTests.swift

 Tests for the Image component in the ActionUI component library.
 Verifies JSON decoding, Props reading, and view construction.
*/

import XCTest
import ImageIO
import SwiftUI
@testable import ActionUI

@MainActor
final class ImageTests: XCTestCase {
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
    
    func testImageConstruction() throws {
        let elementDict: [String: Any] = [
            "id": 1,
            "type": "Image",
            "properties": [
                "systemName": "star.fill",
                "resizable": true,
                "contentMode": "fit",
                "padding": 10.0
            ]
        ]
        let element = try ActionUIElement(from: elementDict, logger: logger)
        let properties = element.properties
        let viewModel = ViewModel()
        let view = ActionUIRegistry.shared.buildView(for: element, model: viewModel, windowUUID: windowUUID, properties: properties)
        
        logger.log("After buildView viewModel = \(String(describing: viewModel))", .debug)
        
        XCTAssertFalse(view is SwiftUI.EmptyView, "View should be an EmptyView")
    }
    
    func testImageJSONDecoding() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Image",
            "properties": {
                "systemName": "star.fill",
                "resizable": true,
                "contentMode": "fit",
                "padding": 10.0,
                "offset": {"x": 5.0, "y": -5.0}
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "star.fill", "systemName should be star.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, true, "resizable should be true")
        XCTAssertEqual(element.properties["contentMode"] as? String, "fit", "contentMode should be fit")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 10.0, "padding should be 10.0")
        if let offset = element.properties["offset"] as? [String: Any] {
            XCTAssertEqual(offset.cgFloat(forKey: "x"), 5.0, "offset.x should be 5.0")
            XCTAssertEqual(offset.cgFloat(forKey: "y"), -5.0, "offset.y should be -5.0")
        } else {
            XCTFail("offset should be valid dictionary")
        }
    }
    
    func testImagePropsValid() {
        let properties: [String: Any] = [
            "systemName": "star.fill",
            "resizable": true,
            "contentMode": "fit",
            "imageScale": "large",
            "padding": 10.0
        ]
        
        let props = Image.Props(properties)
        let mods = BaseModifiers(properties)
        
        XCTAssertEqual(props.sources, [.systemName("star.fill")], "systemName should be preserved")
        XCTAssertTrue(props.resizable, "resizable should be preserved")
        XCTAssertEqual(props.contentMode, .fit, "contentMode should be preserved")
        XCTAssertEqual(props.imageScale, .large, "imageScale should be preserved")
        XCTAssertEqual(mods.padding, .uniform(10.0), "padding should be passed through")
    }
    
    func testImagePropsIgnoreInvalidValues() {
        let properties: [String: Any] = [
            "systemName": 123,
            "resizable": "true",
            "contentMode": "invalid",
            "imageScale": "huge",
            "filePath": "/path/to/doc.txt"
        ]
        
        let props = Image.Props(properties)
        
        XCTAssertTrue(props.sources.allSatisfy { if case .systemName = $0 { return false } else { return true } }, "Invalid systemName should be ignored")
        XCTAssertFalse(props.resizable, "Invalid resizable should be ignored")
        XCTAssertNil(props.contentMode, "Invalid contentMode should be nil")
        XCTAssertNil(props.imageScale, "Invalid imageScale should be nil")
        // A filePath that is not an image or PDF is kept as a source; the renderer skips it.
        XCTAssertEqual(props.sources, [.filePath("/path/to/doc.txt")], "only the filePath is a String source")
    }
    
    func testImagePropsMissing() {
        let properties: [String: Any] = [:]
        
        let props = Image.Props(properties)
        
        XCTAssertTrue(props.sources.isEmpty, "Empty properties should result in no sources")
        XCTAssertFalse(props.resizable, "Missing resizable should be the default")
        XCTAssertNil(props.contentMode, "Missing contentMode should be nil")
        XCTAssertNil(props.imageScale, "Missing imageScale should be nil")
    }
    
    func testImagePropsFilePathValid() {
        let properties: [String: Any] = [
            "filePath": "/path/to/image.jpg",
            "resizable": false,
            "contentMode": "fill",
            "imageScale": "small"
        ]

        let props = Image.Props(properties)

        XCTAssertEqual(props.sources, [.filePath("/path/to/image.jpg")], "Valid filePath should be preserved")
        XCTAssertFalse(props.resizable, "resizable should be preserved")
        XCTAssertEqual(props.contentMode, .fill, "contentMode should be preserved")
        XCTAssertEqual(props.imageScale, .small, "imageScale should be preserved")
    }

    func testImageContentModeValid() {
        let fitProps: [String: Any] = ["systemName": "star", "contentMode": "fit"]
        XCTAssertEqual(Image.Props(fitProps).contentMode, .fit, "contentMode 'fit' should be preserved")

        let fillProps: [String: Any] = ["systemName": "star", "contentMode": "fill"]
        XCTAssertEqual(Image.Props(fillProps).contentMode, .fill, "contentMode 'fill' should be preserved")
    }

    func testImageContentModeInvalid() {
        let properties: [String: Any] = ["systemName": "star", "contentMode": "stretch"]
        let props = Image.Props(properties)
        XCTAssertNil(props.contentMode, "Invalid contentMode should be ignored")
    }

    func testImageScaleModeIsNoLongerRead() {
        // scaleMode, the old name of contentMode, was removed
        let properties: [String: Any] = ["systemName": "star", "scaleMode": "fill"]
        let props = Image.Props(properties)
        XCTAssertNil(props.contentMode, "scaleMode should be ignored")
    }
    
    func testImageJSONDecodingWithImageScale() throws {
        let jsonString = """
        {
            "id": 1,
            "type": "Image",
            "properties": {
                "systemName": "heart.fill",
                "resizable": false,
                "imageScale": "small",
                "padding": 5.0
            }
        }
        """
        guard let jsonData = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert JSON string to Data")
            return
        }
        
        let actionUIModel = ActionUIModel.shared
        
        // Parse JSON into ActionUIElement
        let element = try actionUIModel.loadDescription(from: jsonData, format: "json", windowUUID: windowUUID)
                
        XCTAssertEqual(element.id, 1, "Element ID should be 1")
        XCTAssertEqual(element.type, "Image", "Element type should be Image")
        XCTAssertEqual(element.properties["systemName"] as? String, "heart.fill", "systemName should be heart.fill")
        XCTAssertEqual(element.properties["resizable"] as? Bool, false, "resizable should be false")
        XCTAssertEqual(element.properties["imageScale"] as? String, "small", "imageScale should be small")
        XCTAssertEqual(element.properties.cgFloat(forKey: "padding"), 5.0, "padding should be 5.0")
    }
}

// A filePath a document names could be a device or a named pipe; reading one on the main thread
// would never finish (/dev/zero) or never begin (a pipe nobody writes to). Only a regular file is
// opened; anything else shows the placeholder, at once.
extension ImageTests {
    func testAFilePathThatIsNotARegularFileShowsThePlaceholder() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("image-path-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let pipe = folder.appendingPathComponent("pipe.png")
        XCTAssertEqual(mkfifo(pipe.path, 0o600), 0)
        let deviceLink = folder.appendingPathComponent("zero.png")
        try FileManager.default.createSymbolicLink(at: deviceLink, withDestinationURL: URL(fileURLWithPath: "/dev/zero"))

        let placeholder = SwiftUI.Image(systemName: "photo")
        for path in ["/dev/zero", pipe.path, deviceLink.path, folder.path] {
            XCTAssertEqual(SwiftUI.Image(contentsOfFile: path), placeholder, path)
            XCTAssertEqual(SwiftUI.Image(from: path, interpretation: "path"), placeholder, path)
        }
    }

    /// A real PNG of `width` x `height` pixels, written by ImageIO.
    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    func testAnImageWithMorePixelsThanTheCapIsNotDecoded() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-pixels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saved = ImageSource.maximumPixelCount
        defer {
            ImageSource.maximumPixelCount = saved
            try? FileManager.default.removeItem(at: folder)
        }
        XCTAssertEqual(saved, 8192 * 8192, "64 megapixels")
        let file = folder.appendingPathComponent("image.png")
        try Self.png(width: 100, height: 100).write(to: file)
        ImageSource.maximumPixelCount = 100 * 100
        XCTAssertFalse(ImageHelper.declaresTooManyPixels(file.path), "exactly the cap")
        ImageSource.maximumPixelCount = 100 * 100 - 1
        XCTAssertTrue(ImageHelper.declaresTooManyPixels(file.path), "one pixel over")
        XCTAssertFalse(ImageHelper.declaresTooManyPixels(folder.appendingPathComponent("missing.png").path), "no size: goes on")
        XCTAssertTrue(ImageSource.isTooLarge(width: Int(Int32.max), height: Int(Int32.max)), "no overflow")
    }

    func testLessTrustedContentReadsOnlyTheAppsOwnImageFiles() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-reads-\(UUID().uuidString)")
        let resources = folder.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        defer {
            ActionUIResourceFolder.path = nil
            try? FileManager.default.removeItem(at: folder)
        }
        ActionUIResourceFolder.path = resources.path
        let inside = resources.appendingPathComponent("in.png")
        let outside = folder.appendingPathComponent("out.png")
        try Self.png(width: 4, height: 4).write(to: inside)
        try Self.png(width: 4, height: 4).write(to: outside)
        let document = Data(#"{"id": 7, "type": "Image", "properties": {"filePath": "x.png"}}"#.utf8)
        let remote = UUID().uuidString
        ActionUIModel.shared.logger = ConsoleLogger(maxLevel: .error)
        defer { ActionUIModel.shared.logger = logger }
        _ = try ActionUIDocumentLoader.load(data: document, format: "json", windowUUID: remote, isContentView: true, parentID: 0,
                                            source: .remote(URL(string: "https://example.com/v.json")!))
        _ = try ActionUIDocumentLoader.load(data: document, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        let placeholder = SwiftUI.Image(systemName: ImageSource.placeholderSymbol)
        XCTAssertFalse(ActionUIModel.shared.readsLocalFile(outside.path, windowUUID: remote, viewID: 7))
        XCTAssertTrue(ActionUIModel.shared.readsLocalFile(inside.path, windowUUID: remote, viewID: 7), "the app's own resources")
        XCTAssertTrue(ActionUIModel.shared.readsLocalFile(outside.path, windowUUID: windowUUID, viewID: 7), "the host's content reads anything")
        XCTAssertEqual(ImageHelper.image(from: outside.path, interpretation: "path", windowUUID: remote, viewID: 7), placeholder)
        XCTAssertNotEqual(ImageHelper.image(from: inside.path, interpretation: "path", windowUUID: remote, viewID: 7), placeholder)
        XCTAssertNotEqual(ImageHelper.image(from: outside.path, interpretation: "path", windowUUID: windowUUID, viewID: 7), placeholder)
        XCTAssertNil(ImageHelper.loadableImageURL(outside, windowUUID: remote, viewID: 7), "a file: AsyncImage")
        XCTAssertEqual(ImageHelper.loadableImageURL(inside, windowUUID: remote, viewID: 7), inside)
        XCTAssertEqual(ImageHelper.loadableImageURL(URL(string: "https://example.com/a.png"), windowUUID: remote, viewID: 7)?.absoluteString,
                       "https://example.com/a.png", "an address is not a local file")
        // Canvas: the file paths of image operations, nested ones too, are asked about before drawing.
        let ops: [[String: Any]] = [
            ["type": "image", "filePath": "/a.png", "frame": [0, 0, 1, 1]],
            ["type": "layer", "operations": [["type": "image", "filePath": "/b.png", "frame": [0, 0, 1, 1]], ["type": "fill"]]],
            ["type": "image", "systemName": "star", "frame": [0, 0, 1, 1]],
        ]
        XCTAssertEqual(CanvasRenderer.imageFilePaths(in: ops), ["/a.png", "/b.png"])
    }

    func testATemplateRowImageReadsAsItsContainersContent() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("actionui-template-reads-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appendingPathComponent("photo.png")
        try Self.png(width: 4, height: 4).write(to: file)
        let document = Data(#"{"id": 20, "type": "HStack", "template": {"type": "Image", "properties": {"filePath": "$1"}}}"#.utf8)
        let remote = UUID().uuidString
        ActionUIModel.shared.logger = ConsoleLogger(maxLevel: .error)
        defer { ActionUIModel.shared.logger = logger }
        let hostStack = try ActionUIDocumentLoader.load(data: document, format: "json", windowUUID: windowUUID, isContentView: true, parentID: 0, source: nil)
        let remoteStack = try ActionUIDocumentLoader.load(data: document, format: "json", windowUUID: remote, isContentView: true, parentID: 0,
                                                          source: .remote(URL(string: "https://example.com/v.json")!))
        let placeholder = SwiftUI.Image(systemName: ImageSource.placeholderSymbol)
        // A template row's element has no view model of its own: it asks with its container's id.
        func rowImage(_ stack: ActionUIElement, window: String) throws -> SwiftUI.Image? {
            let template = try XCTUnwrap(stack.subviews?["template"] as? ActionUIElement)
            let properties = TemplateHelper.instanceProperties(of: template, row: [file.path], logger: logger)
            let model = ViewModel()
            model.templateContext = TemplateContext(parentID: stack.id, rowIndex: 0, row: [file.path])
            model.seedProperties(properties)
            return Image.buildView(template, model, window, properties, logger) as? SwiftUI.Image
        }
        XCTAssertNotEqual(try rowImage(hostStack, window: windowUUID), placeholder, "the host's row reads its file")
        XCTAssertEqual(try rowImage(remoteStack, window: remote), placeholder, "a less-trusted row does not")
    }
}
