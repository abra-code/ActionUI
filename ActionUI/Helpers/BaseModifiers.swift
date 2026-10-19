// Helpers/BaseModifiers.swift
/*
 BaseModifiers: the base View properties every element accepts (padding, frame, colors, actions,
 accessibility, presentation options, ...), parsed from the raw properties dictionary into typed
 fields. A renderer builds it at the start of every render and reads only its fields, so the key
 names, defaults and rules exist once and every renderer applies the same thing.

 Built fresh each time from the current properties: never stored. A value that is not usable comes
 out nil (or the documented default), which is what removing it during validation did. The rules
 for structured values are in ModifierParsing.

 Portable on purpose: Foundation types only. Colors and fonts stay as given (the renderer resolves
 them) until they get portable descriptions of their own.
*/

import Foundation

struct BaseModifiers {

    // MARK: - Portable names

    /// The nine alignment names, also used for anchors (unit points), which have the same names.
    enum AlignmentName: String, Sendable, CaseIterable {
        case center, leading, trailing, top, bottom, topLeading, topTrailing, bottomLeading, bottomTrailing
    }

    enum EdgeName: String, Sendable, CaseIterable {
        case top, bottom, leading, trailing
    }

    // MARK: - Structured values

    enum Padding: Equatable, Sendable {
        /// "default": the platform's standard padding.
        case system
        case uniform(Double)
        case edges(top: Double, leading: Double, bottom: Double, trailing: Double)
    }

    struct Frame: Equatable, Sendable {
        var width: Double?
        var height: Double?
        var minWidth: Double?
        var idealWidth: Double?
        var maxWidth: Double?
        var minHeight: Double?
        var idealHeight: Double?
        var maxHeight: Double?
        /// nil: centered.
        var alignment: AlignmentName?

        /// The fixed form: width and height.
        var isFixed: Bool { width != nil || height != nil }
        /// The flexible form: minimum, ideal and maximum per axis.
        var isFlexible: Bool {
            minWidth != nil || idealWidth != nil || maxWidth != nil
                || minHeight != nil || idealHeight != nil || maxHeight != nil
        }
    }

    struct Offset: Equatable, Sendable {
        var x: Double
        var y: Double
    }

    struct Scale: Equatable, Sendable {
        var x: Double
        var y: Double
        var anchor: AlignmentName
    }

    struct Shadow: Equatable, Sendable {
        /// nil: the renderer's default shadow color.
        var color: String?
        var radius: Double
        var x: Double
        var y: Double
    }

    struct Border: Equatable, Sendable {
        /// nil: black.
        var color: String?
        var width: Double
    }

    enum ClipShape: Equatable, Sendable {
        case rectangle, circle, capsule, ellipse
        case roundedRectangle(radiusX: Double, radiusY: Double)
    }

    struct SafeArea: Equatable, Sendable {
        enum Regions: String, Sendable { case all, container, keyboard }
        enum Edges: String, Sendable { case all, top, bottom, leading, trailing, horizontal, vertical }
        var regions: Regions = .all
        var edges: Edges = .all
    }

    struct Animation: Equatable, Sendable {
        enum Curve: String, Sendable, CaseIterable {
            case `default`, linear, easeIn, easeOut, easeInOut, spring, bouncy, smooth, snappy, interactiveSpring
        }
        var curve: Curve
        var duration: Double?
        var delay: Double = 0
        var speed: Double = 1
        /// The property or state whose changes run the animation; nil: every change of the element.
        var watchedValue: String?

        init(curve: Curve) {
            self.curve = curve
        }
    }

    indirect enum Transition: Equatable, Sendable {
        case identity, opacity, slide
        /// factor nil: the renderer's default scale transition.
        case scale(factor: Double?, anchor: AlignmentName)
        case move(edge: EdgeName)
        case offset(x: Double, y: Double)
        case asymmetric(insertion: Transition, removal: Transition)
        case combined([Transition])
    }

    enum ColumnWidth: Equatable, Sendable {
        case fixed(Double)
        case range(min: Double?, ideal: Double, max: Double?)
    }

    enum ModifierKey: String, Sendable, CaseIterable {
        case command, shift, option, control, capslock
    }

    struct KeyboardShortcut: Equatable, Sendable {
        /// One character, or a special key name such as "return" or "upArrow".
        var key: String
        var modifiers: Set<ModifierKey>
    }

    struct Drop: Equatable, Sendable {
        var actionID: String
        /// Uniform type identifiers; never empty.
        var types: [String]
        var targetedActionID: String?
    }

    struct Searchable: Equatable, Sendable {
        /// Never empty.
        var actionID: String
        var prompt: String?
    }

    // MARK: - Style names

    enum ButtonStyleName: String, Sendable, CaseIterable {
        case automatic, plain, borderless, bordered, borderedProminent
    }

    enum ControlSizeName: String, Sendable, CaseIterable {
        case mini, small, regular, large, extraLarge
    }

    enum ScrollContentBackground: String, Sendable, CaseIterable {
        case visible, hidden, automatic
    }

    enum TextSelection: String, Sendable, CaseIterable {
        case enabled, disabled
    }

    enum TextAlignment: String, Sendable, CaseIterable {
        case leading, center, trailing
    }

    enum TitleDisplayMode: String, Sendable, CaseIterable {
        case automatic, inline, large, inlineLarge
    }

    // MARK: - Fields, in the order the SwiftUI renderer applies them

    var padding: Padding?
    /// A text style or font name (String), or a font dictionary; nil for anything else.
    var font: Any?
    var foregroundStyle: String?
    var tint: String?
    var disabled: Bool?
    var hidden: Bool
    var frame: Frame?
    var background: String?
    var backgroundAlignment: AlignmentName
    var cornerRadius: Double?
    var clipShape: ClipShape?
    var offset: Offset?
    /// Between 0 and 1.
    var opacity: Double?
    var textSelection: TextSelection?
    var rotationDegrees: Double?
    var scale: Scale?
    var multilineTextAlignment: TextAlignment?
    var zIndex: Double?
    var border: Border?
    var overlayAlignment: AlignmentName
    var ignoresSafeArea: SafeArea?
    var buttonStyle: ButtonStyleName?
    var controlSize: ControlSizeName?
    var labelsHidden: Bool
    var scrollContentBackground: ScrollContentBackground?
    var shadow: Shadow?
    var animation: Animation?
    var transition: Transition?
    var openURLActionID: String?
    var onAppearActionID: String?
    var onDisappearActionID: String?
    var onHoverActionID: String?
    var columnWidth: ColumnWidth?
    var keyboardShortcut: KeyboardShortcut?
    var navigationTitle: String?
    var titleDisplayMode: TitleDisplayMode?
    var help: String?
    var accessibilityLabel: String?
    var accessibilityHint: String?
    var accessibilityHidden: Bool?
    var accessibilityIdentifier: String?
    var drop: Drop?
    var sheetOnDismissActionID: String?
    var fullScreenCoverOnDismissActionID: String?
    var searchable: Searchable?
    var popoverArrowEdge: EdgeName
    var popoverActionID: String?

    init(_ properties: [String: Any]) {
        padding = ModifierParsing.padding(properties["padding"])
        let font = properties["font"]
        self.font = (font is String || font is [String: Any]) ? font : nil
        foregroundStyle = properties["foregroundStyle"] as? String
        tint = properties["tint"] as? String
        disabled = properties["disabled"] as? Bool
        hidden = properties["hidden"] as? Bool == true
        frame = ModifierParsing.frame(properties["frame"])
        background = properties["background"] as? String
        backgroundAlignment = (properties["backgroundAlignment"] as? String).flatMap(AlignmentName.init(rawValue:)) ?? .center
        cornerRadius = properties.double(forKey: "cornerRadius")
        clipShape = ModifierParsing.clipShape(properties["clipShape"])
        offset = ModifierParsing.offset(properties["offset"])
        opacity = properties.double(forKey: "opacity").flatMap { (0.0...1.0).contains($0) ? $0 : nil }
        textSelection = (properties["textSelection"] as? String).flatMap(TextSelection.init(rawValue:))
        rotationDegrees = properties.double(forKey: "rotationEffect")
        scale = ModifierParsing.scale(properties["scaleEffect"])
        multilineTextAlignment = (properties["multilineTextAlignment"] as? String).flatMap(TextAlignment.init(rawValue:))
        zIndex = properties.double(forKey: "zIndex")
        border = ModifierParsing.border(properties["border"])
        overlayAlignment = (properties["overlayAlignment"] as? String).flatMap(AlignmentName.init(rawValue:)) ?? .center
        if properties["ignoresSafeArea"] as? Bool == true {
            ignoresSafeArea = SafeArea()
        } else if let spec = properties["ignoresSafeArea"] as? [String: Any] {
            ignoresSafeArea = SafeArea(
                regions: (spec["regions"] as? String).flatMap(SafeArea.Regions.init(rawValue:)) ?? .all,
                edges: (spec["edges"] as? String).flatMap(SafeArea.Edges.init(rawValue:)) ?? .all
            )
        } else {
            ignoresSafeArea = nil
        }
        buttonStyle = (properties["buttonStyle"] as? String).flatMap(ButtonStyleName.init(rawValue:))
        controlSize = (properties["controlSize"] as? String).flatMap(ControlSizeName.init(rawValue:))
        labelsHidden = properties["labelsHidden"] as? Bool == true
        scrollContentBackground = (properties["scrollContentBackground"] as? String).flatMap(ScrollContentBackground.init(rawValue:))
        shadow = ModifierParsing.shadow(properties["shadow"])
        animation = ModifierParsing.animation(properties["animation"])
        transition = ModifierParsing.transition(properties["transition"])
        openURLActionID = properties["openURLActionID"] as? String
        onAppearActionID = properties["onAppearActionID"] as? String
        onDisappearActionID = properties["onDisappearActionID"] as? String
        onHoverActionID = properties["onHoverActionID"] as? String
        columnWidth = ModifierParsing.columnWidth(properties["navigationSplitViewColumnWidth"])
        keyboardShortcut = ModifierParsing.keyboardShortcut(properties["keyboardShortcut"])
        navigationTitle = properties["navigationTitle"] as? String
        titleDisplayMode = (properties["toolbarTitleDisplayMode"] as? String).flatMap(TitleDisplayMode.init(rawValue:))
        help = properties["help"] as? String
        accessibilityLabel = properties["accessibilityLabel"] as? String
        accessibilityHint = properties["accessibilityHint"] as? String
        accessibilityHidden = properties["accessibilityHidden"] as? Bool
        accessibilityIdentifier = properties["accessibilityIdentifier"] as? String
        if let actionID = properties["onDropActionID"] as? String,
           let types = properties["onDropTypes"] as? [String], !types.isEmpty {
            drop = Drop(actionID: actionID, types: types, targetedActionID: properties["onDropTargetedActionID"] as? String)
        } else {
            drop = nil
        }
        sheetOnDismissActionID = properties["sheetOnDismissActionID"] as? String
        fullScreenCoverOnDismissActionID = properties["fullScreenCoverOnDismissActionID"] as? String
        if let spec = properties["searchable"] as? [String: Any],
           let actionID = spec["actionID"] as? String, !actionID.isEmpty {
            searchable = Searchable(actionID: actionID, prompt: spec["prompt"] as? String)
        } else {
            searchable = nil
        }
        popoverArrowEdge = (properties["popoverArrowEdge"] as? String).flatMap(EdgeName.init(rawValue:)) ?? .top
        popoverActionID = properties["popoverActionID"] as? String
    }
}
