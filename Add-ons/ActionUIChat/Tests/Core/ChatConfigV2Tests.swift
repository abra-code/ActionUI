// Add-ons/ActionUIChat/Tests/Core/ChatConfigV2Tests.swift
//
// P2 tests for the person-to-person / group (v2) config layer: the new appearance flags
// (showTimestamps with its alignment-conditional default, showAvatars, showDeliveryStatus),
// the `features` gate object, and `attachActionID`, plus their validate() handling. The
// guardrail: a v1 (single-alignment) document keeps its exact defaults, so these are inert
// unless a document opts in.

import XCTest
@testable import ActionUIChatCore
import ActionUI

private final class ConfigV2Logger: ActionUILogger {
    func log(_ message: String, _ level: LoggerLevel) {}
}

final class ChatConfigV2AppearanceTests: XCTestCase {

    private func config(_ properties: [String: Any]) -> ChatConfig {
        ChatConfig(properties: properties, logger: ConfigV2Logger())
    }

    // showTimestamps defaults to the alignment: ON in dual, OFF in single (so a v1 single
    // document is pixel-identical), and an explicit value always wins.
    func testShowTimestampsDefaultsToAlignment() {
        XCTAssertFalse(config([:]).showTimestamps, "single (default) alignment -> timestamps off")
        XCTAssertFalse(config(["appearance": ["alignment": "single"]]).showTimestamps)
        XCTAssertTrue(config(["appearance": ["alignment": "dual"]]).showTimestamps, "dual alignment -> timestamps on")
    }

    func testShowTimestampsExplicitOverridesTheAlignmentDefault() {
        XCTAssertTrue(config(["appearance": ["alignment": "single", "showTimestamps": true]]).showTimestamps)
        XCTAssertFalse(config(["appearance": ["alignment": "dual", "showTimestamps": false]]).showTimestamps)
    }

    func testShowAvatarsDefaultsFalseAndParses() {
        XCTAssertFalse(config([:]).showAvatars)
        XCTAssertTrue(config(["appearance": ["showAvatars": true]]).showAvatars)
    }

    func testShowDeliveryStatusDefaultsTrueAndParses() {
        XCTAssertTrue(config([:]).showDeliveryStatus)
        XCTAssertFalse(config(["appearance": ["showDeliveryStatus": false]]).showDeliveryStatus)
    }

    func testAlignmentParsesDualWithoutAffectingV1Default() {
        XCTAssertEqual(config([:]).alignment, .single)
        XCTAssertEqual(config(["appearance": ["alignment": "dual"]]).alignment, .dual)
    }
}

final class ChatConfigV2FeaturesTests: XCTestCase {

    private func config(_ properties: [String: Any]) -> ChatConfig {
        ChatConfig(properties: properties, logger: ConfigV2Logger())
    }

    func testFeaturesDefaultAllFalse() {
        let f = config([:]).features
        XCTAssertFalse(f.reactions)
        XCTAssertFalse(f.editing)
        XCTAssertFalse(f.deletion)
        XCTAssertFalse(f.replies)
    }

    func testFeaturesParse() {
        let f = config(["features": ["reactions": true, "editing": true, "deletion": false, "replies": true]]).features
        XCTAssertTrue(f.reactions)
        XCTAssertTrue(f.editing)
        XCTAssertFalse(f.deletion)
        XCTAssertTrue(f.replies)
    }

    func testAttachActionIDParses() {
        XCTAssertNil(config([:]).attachActionID)
        XCTAssertEqual(config(["attachActionID": "chat.attach"]).attachActionID, "chat.attach")
    }
}

final class ChatConfigV2ValidateTests: XCTestCase {

    private func validate(_ properties: [String: Any]) -> [String: Any] {
        ChatConfig.validate(properties, ConfigV2Logger())
    }

    func testFeaturesMustBeObject() {
        XCTAssertNil(validate(["features": "yes"])["features"], "a non-object features is dropped")
    }

    func testValidateDropsUnknownFeatureKeysAndNonBoolValues() {
        let validated = validate(["features": ["reactions": true, "bogus": true, "editing": "yes"]])
        let features = validated["features"] as? [String: Any]
        XCTAssertEqual(features?["reactions"] as? Bool, true, "a known Bool feature survives")
        XCTAssertNil(features?["bogus"], "an unknown feature key is dropped")
        XCTAssertNil(features?["editing"], "a non-Bool feature value is dropped")
    }

    func testAttachActionIDMustBeString() {
        XCTAssertNil(validate(["attachActionID": 42])["attachActionID"], "a non-String attachActionID is dropped")
        XCTAssertEqual(validate(["attachActionID": "chat.attach"])["attachActionID"] as? String, "chat.attach")
    }
}
