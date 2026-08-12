// Tests/Helpers/ContainerActionTests.swift
/*
 ContainerActionTests.swift

 Tests for whole-container tap dispatch: the pure rule deciding WHICH view id and
 row index a tapped VStack / HStack / ZStack dispatches with.

 The identity rule is the whole feature. A container tap that fires with the wrong id is
 worse than one that does not fire at all: the handler runs, addresses some other row, and
 looks like a working feature. That is exactly how the web behaved before this change - it
 dispatched the cloned instance's id, which TemplateHelper forces to 0 - so the rule is
 pinned here rather than inferred from a rendered hierarchy.

 The SwiftUI half - .contentShape(Rectangle()).onTapGesture actually being attached, and a
 nested Button keeping its own tap so the cell action does not also fire - is covered by
 ActionUITestAppUITests/ContainerActionTests.swift, which can press a real target.
*/

import XCTest
import SwiftUI
@testable import ActionUI

@MainActor
final class ContainerActionTests: XCTestCase {
    private var logger: XCTestLogger!
    private var windowUUID: String!

    override func setUp() async throws {
        try await super.setUp()
        logger = XCTestLogger(maxLevel: .verbose)
        ActionUIRegistry.shared.setLogger(logger)
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

    /// A bare VStack element carrying `id`, used only as the identity source for resolve().
    private func container(id: Int) throws -> any ActionUIElementBase {
        let json = "{ \"id\": \(id), \"type\": \"VStack\", \"properties\": {} }"
        return try ActionUIModel.shared.loadDescription(
            from: Data(json.utf8), format: "json", windowUUID: windowUUID
        )
    }

    private func row(parentID: Int, rowIndex: Int) -> TemplateContext {
        TemplateContext(parentID: parentID, rowIndex: rowIndex, row: ["a", "b"])
    }

    /// A bare element of `type` carrying `id`.
    private func element(type: String, id: Int) throws -> any ActionUIElementBase {
        let json = "{ \"id\": \(id), \"type\": \"\(type)\", \"properties\": {} }"
        return try ActionUIModel.shared.loadDescription(
            from: Data(json.utf8), format: "json", windowUUID: windowUUID
        )
    }

    func testAllThreeStackTypesAreTappableAndOtherTypesAreNot() throws {
        // ZStack in particular had no coverage of any kind before this: the wiring is a
        // SwiftUI modifier, so the type list is the only part of it a unit test can reach.
        for type in ["VStack", "HStack", "ZStack"] {
            let dispatch = ContainerAction.resolve(
                element: try element(type: type, id: 5),
                properties: ["actionID": "cell.open"],
                templateContext: nil
            )
            XCTAssertEqual(dispatch, ContainerAction.Dispatch(actionID: "cell.open", viewID: 5, viewPartID: 0),
                           "\(type) should be tappable")
        }
        // Everything else keeps its own actionID semantics (Button, Toggle, ...) or none.
        // This is what stops the change from altering hit-testing across every document.
        for type in ["Text", "Image", "List", "Button", "LazyVGrid"] {
            XCTAssertNil(ContainerAction.resolve(
                element: try element(type: type, id: 5),
                properties: ["actionID": "cell.open"],
                templateContext: nil
            ), "\(type) must not become a container tap target")
        }
    }

    func testAContainerThatDeclaresDisabledIsNotTappable() throws {
        // Checked in resolve rather than left to SwiftUI: View.applyModifiers puts
        // `.disabled()` around the container's own subtree, and the tap is attached outside
        // that, so the environment would not suppress it. (An ANCESTOR's disablement does
        // reach the tap through the environment - ContainerActionView reads \.isEnabled.)
        let dispatch = ContainerAction.resolve(
            element: try container(id: 5),
            properties: ["actionID": "cell.open", "disabled": true],
            templateContext: nil
        )
        XCTAssertNil(dispatch)
    }

    func testDisabledFalseIsStillTappable() throws {
        let dispatch = ContainerAction.resolve(
            element: try container(id: 5),
            properties: ["actionID": "cell.open", "disabled": false],
            templateContext: nil
        )
        XCTAssertEqual(dispatch, ContainerAction.Dispatch(actionID: "cell.open", viewID: 5, viewPartID: 0))
    }

    func testNoActionIDMeansNoTapTarget() throws {
        let element = try container(id: 5)
        XCTAssertNil(ContainerAction.resolve(element: element, properties: [:], templateContext: nil))
    }

    func testBlankActionIDIsRefusedRatherThanWiringADeadTapTarget() throws {
        let element = try container(id: 5)
        XCTAssertNil(ContainerAction.resolve(
            element: element, properties: ["actionID": ""], templateContext: nil
        ))
        XCTAssertNil(ContainerAction.resolve(
            element: element, properties: ["actionID": "   "], templateContext: nil
        ))
    }

    func testNonStringActionIDIsRefused() throws {
        let element = try container(id: 5)
        XCTAssertNil(ContainerAction.resolve(
            element: element, properties: ["actionID": 42], templateContext: nil
        ))
    }

    func testOutsideATemplateAContainerDispatchesAsItself() throws {
        let element = try container(id: 5)
        let dispatch = ContainerAction.resolve(
            element: element, properties: ["actionID": "cell.open"], templateContext: nil
        )
        XCTAssertEqual(dispatch, ContainerAction.Dispatch(actionID: "cell.open", viewID: 5, viewPartID: 0))
    }

    func testInsideATemplateRowItDispatchesTheOwningContainerIDAndRowIndex() throws {
        // The cloned instance's own id identifies nothing - the context is the only place
        // row identity exists. This is the case the gap was about.
        let element = try container(id: 0)
        let dispatch = ContainerAction.resolve(
            element: element,
            properties: ["actionID": "row.open"],
            templateContext: row(parentID: 100, rowIndex: 4)
        )
        XCTAssertEqual(dispatch, ContainerAction.Dispatch(actionID: "row.open", viewID: 100, viewPartID: 4))
    }

    func testRowZeroIsARealRowNotAnAbsentContext() throws {
        // Pins that the PRESENCE of a context, not the value of the row index, decides
        // whose id is dispatched - so the first row is not silently treated as "no
        // template". Cheap here; load-bearing on the web, where 0 is falsy.
        let element = try container(id: 0)
        let dispatch = ContainerAction.resolve(
            element: element,
            properties: ["actionID": "row.open"],
            templateContext: row(parentID: 100, rowIndex: 0)
        )
        XCTAssertEqual(dispatch, ContainerAction.Dispatch(actionID: "row.open", viewID: 100, viewPartID: 0))
    }

    func testTheTemplateContextWinsOverAContainerThatKeptARealID() throws {
        // A template instance normally has id 0, but nothing guarantees it: an author can
        // put an id on the template's root element. Row identity still comes from the
        // context, matching Button.swift, so a cell and a button inside it agree.
        let element = try container(id: 77)
        let dispatch = ContainerAction.resolve(
            element: element,
            properties: ["actionID": "row.open"],
            templateContext: row(parentID: 100, rowIndex: 2)
        )
        XCTAssertEqual(dispatch, ContainerAction.Dispatch(actionID: "row.open", viewID: 100, viewPartID: 2))
    }
}
