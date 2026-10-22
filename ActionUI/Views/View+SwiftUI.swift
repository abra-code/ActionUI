// SwiftUI rendering of View; its portable part is in Core/Elements/View.swift.

import SwiftUI

private func resolveAlignment(_ name: BaseModifiers.AlignmentName?) -> Alignment {
    switch name ?? .center {
    case .center:         return .center
    case .leading:        return .leading
    case .trailing:       return .trailing
    case .top:            return .top
    case .bottom:         return .bottom
    case .topLeading:     return .topLeading
    case .topTrailing:    return .topTrailing
    case .bottomLeading:  return .bottomLeading
    case .bottomTrailing: return .bottomTrailing
    }
}

// safe-area helpers (ignoresSafeArea / safeAreaInset).
private func resolveSafeAreaEdges(_ edges: BaseModifiers.SafeArea.Edges) -> Edge.Set {
    switch edges {
    case .all:        return .all
    case .top:        return .top
    case .bottom:     return .bottom
    case .leading:    return .leading
    case .trailing:   return .trailing
    case .horizontal: return .horizontal
    case .vertical:   return .vertical
    }
}

private func resolveSafeAreaRegions(_ regions: BaseModifiers.SafeArea.Regions) -> SafeAreaRegions {
    switch regions {
    case .all:       return .all
    case .container: return .container
    case .keyboard:  return .keyboard
    }
}

// safeAreaInset alignment: a top/bottom inset aligns horizontally, a leading/trailing inset vertically.
private func resolveSafeAreaHorizontalAlignment(_ string: String?) -> HorizontalAlignment {
    switch string {
    case "leading":  return .leading
    case "trailing": return .trailing
    default:         return .center
    }
}

private func resolveSafeAreaVerticalAlignment(_ string: String?) -> VerticalAlignment {
    switch string {
    case "top":    return .top
    case "bottom": return .bottom
    default:       return .center
    }
}

private func resolveUnitPoint(_ name: BaseModifiers.AlignmentName) -> UnitPoint {
    switch name {
    case .center:         return .center
    case .leading:        return .leading
    case .trailing:       return .trailing
    case .top:            return .top
    case .bottom:         return .bottom
    case .topLeading:     return .topLeading
    case .topTrailing:    return .topTrailing
    case .bottomLeading:  return .bottomLeading
    case .bottomTrailing: return .bottomTrailing
    }
}

private func resolveAnimation(_ config: BaseModifiers.Animation) -> Animation {
    let duration = config.duration

    var animation: Animation
    switch config.curve {
    case .linear:            animation = duration != nil ? .linear(duration: duration!) : .linear
    case .easeIn:            animation = duration != nil ? .easeIn(duration: duration!) : .easeIn
    case .easeOut:           animation = duration != nil ? .easeOut(duration: duration!) : .easeOut
    case .easeInOut:         animation = duration != nil ? .easeInOut(duration: duration!) : .easeInOut
    case .spring:            animation = duration != nil ? .spring(duration: duration!) : .spring
    case .bouncy:            animation = duration != nil ? .bouncy(duration: duration!) : .bouncy
    case .smooth:            animation = duration != nil ? .smooth(duration: duration!) : .smooth
    case .snappy:            animation = duration != nil ? .snappy(duration: duration!) : .snappy
    case .interactiveSpring: animation = .interactiveSpring
    case .default:           animation = .default
    }

    if config.delay > 0 { animation = animation.delay(config.delay) }
    if config.speed != 1.0 { animation = animation.speed(config.speed) }
    return animation
}

private func resolveAnimationWatchedValue(
    named target: String?,
    mutationToken: Int,
    properties: [String: Any],
    states: [String: Any],
    viewValue: Any?
) -> AnyHashable {
    guard let target else { return mutationToken }
    if let v = properties[target] as? AnyHashable { return v }
    if let v = states[target] as? AnyHashable { return v }
    if target == "value", let v = viewValue as? AnyHashable { return v }
    return AnyHashable(0)
}

private func resolveEdge(_ name: BaseModifiers.EdgeName) -> Edge {
    switch name {
    case .top:      return .top
    case .bottom:   return .bottom
    case .leading:  return .leading
    case .trailing: return .trailing
    }
}

// Resolves a parsed `transition` (ModifierParsing.transition) to an AnyTransition.
// The element's `.transition()` plays only when the view is structurally inserted/removed inside an
// animated transaction (WindowModel wraps insert/remove in withAnimation when `transition` is set).
private func resolveTransition(_ transition: BaseModifiers.Transition) -> AnyTransition {
    switch transition {
    case .identity: return .identity
    case .opacity:  return .opacity
    case .slide:    return .slide
    case .scale(let factor, let anchor):
        if let factor {
            return .scale(scale: factor, anchor: resolveUnitPoint(anchor))
        }
        return .scale
    case .move(let edge):
        return .move(edge: resolveEdge(edge))
    case .offset(let x, let y):
        return .offset(x: x, y: y)
    case .asymmetric(let insertion, let removal):
        return .asymmetric(insertion: resolveTransition(insertion), removal: resolveTransition(removal))
    case .combined(let parts):
        // ModifierParsing never returns an empty combination.
        let resolved = parts.map(resolveTransition)
        return resolved.dropFirst().reduce(resolved[0]) { $0.combined(with: $1) }
    }
}

extension View: ActionUISwiftUIRenderer {
    static var buildView: (any ActionUIElementBase, ViewModel, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { element, model, windowUUID, properties, logger in
        SwiftUI.EmptyView()
    }
    
    static var applyModifiers: (any SwiftUI.View, any ActionUIElementBase, String, [String: Any], any ActionUILogger) -> any SwiftUI.View = { view, element, windowUUID, properties, logger in
        var modifiedView = view
        // Every base property, parsed once; below, only the subviews (background, overlay, sheet, ...)
        // and the animation's watched value are read from anything else.
        let mods = BaseModifiers(properties)

        // Do not handle actionID here; concrete views (e.g., DatePicker) should handle actionID in buildView with specific context (e.g., windowUUID, viewID, viewPartID)

        switch mods.padding {
        case .edges(let top, let leading, let bottom, let trailing):
            modifiedView = modifiedView.padding(EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing))
        case .uniform(let padding):
            modifiedView = modifiedView.padding(padding)
        case .system:
            modifiedView = modifiedView.padding()
        case nil:
            break
        }

        if let font = mods.font {
            modifiedView = modifiedView.font(FontHelper.resolveFont(font, logger))
        }

        // Use foregroundStyle with resolveShapeStyle. A present-but-unresolvable color string
        // warns (matching the web renderer) so an unsupported SwiftUI color idiom surfaces at
        // authoring time instead of silently rendering nothing.
        if let foregroundStyle = mods.foregroundStyle {
            if let style = ColorHelper.resolveShapeStyle(foregroundStyle) {
                modifiedView = modifiedView.foregroundStyle(style)
            } else if !foregroundStyle.isEmpty {
                logger.log("Unknown color \"\(foregroundStyle)\"", .warning)
            }
        }

        // Use tint with resolveShapeStyle
        if let tint = mods.tint {
            if let style = ColorHelper.resolveShapeStyle(tint) {
                modifiedView = modifiedView.tint(style)
            } else if !tint.isEmpty {
                logger.log("Unknown color \"\(tint)\"", .warning)
            }
        }

        if let disabled = mods.disabled {
            modifiedView = modifiedView.disabled(disabled)
        }

        // frame is applied BEFORE the decoration below (background color/view,
        // cornerRadius, clipShape) so a background FILLS the frame and the rounding/
        // clip shapes that filled, sized box - the intuitive "sized box" semantics
        // and the cross-platform contract shared with Web and Android. Padding is
        // innermost (applied first
        // above), so a padded element with NO frame is unchanged - the background
        // still fills content+padding (the pill/badge idiom). Changing this from the
        // old background-before-frame order is what makes a styled, fixed/flex-sized
        // box keep its fill when its content is empty or short.
        if let frame = mods.frame {
            let alignment = resolveAlignment(frame.alignment)
            if frame.isFixed {
                modifiedView = modifiedView.frame(
                    width: frame.width.map { CGFloat($0) },
                    height: frame.height.map { CGFloat($0) },
                    alignment: alignment
                )
            } else if frame.isFlexible {
                modifiedView = modifiedView.frame(
                    minWidth: frame.minWidth.map { CGFloat($0) },
                    idealWidth: frame.idealWidth.map { CGFloat($0) },
                    maxWidth: frame.maxWidth.map { CGFloat($0) },
                    minHeight: frame.minHeight.map { CGFloat($0) },
                    idealHeight: frame.idealHeight.map { CGFloat($0) },
                    maxHeight: frame.maxHeight.map { CGFloat($0) },
                    alignment: alignment
                )
            } else {
                // Apply frame with only alignment
                modifiedView = modifiedView.frame(alignment: alignment)
            }
        }

        // Use background with resolveShapeStyle. Applied AFTER frame, so it fills the
        // framed size (was applied before frame, where it hugged the content).
        if let background = mods.background {
            if let style = ColorHelper.resolveShapeStyle(background) {
                modifiedView = modifiedView.background(style)
            } else if !background.isEmpty {
                logger.log("Unknown color \"\(background)\"", .warning)
            }
        }

        // Apply view-based backgroundView modifier (also fills the framed size).
        if let bgElement = element.subviews?["background"] as? any ActionUIElementBase,
           let windowModel = ActionUIModel.shared.windowModels[windowUUID],
           let bgModel = windowModel.viewModels[bgElement.id] {
            let alignment = resolveAlignment(mods.backgroundAlignment)
            modifiedView = modifiedView.background(alignment: alignment) {
                ActionUIView(element: bgElement, model: bgModel, windowUUID: windowUUID)
            }
        }

        // cornerRadius then clipShape, applied after frame+background so they round /
        // clip the filled, framed box (and, with no background, clip a sized element -
        // e.g. an avatar Image - after it is sized, the correct SwiftUI order).
        if let cornerRadius = mods.cornerRadius {
            modifiedView = modifiedView.cornerRadius(cornerRadius)
        }

        switch mods.clipShape {
        case .circle:
            modifiedView = modifiedView.clipShape(SwiftUI.Circle())
        case .capsule:
            modifiedView = modifiedView.clipShape(SwiftUI.Capsule())
        case .ellipse:
            modifiedView = modifiedView.clipShape(SwiftUI.Ellipse())
        case .rectangle:
            modifiedView = modifiedView.clipShape(SwiftUI.Rectangle())
        case .roundedRectangle(let radiusX, let radiusY):
            modifiedView = modifiedView.clipShape(SwiftUI.RoundedRectangle(cornerSize: CGSize(width: radiusX, height: radiusY)))
        case nil:
            break
        }

        if let offset = mods.offset {
            modifiedView = modifiedView.offset(x: offset.x, y: offset.y)
            logger.log("Applied offset: x=\(offset.x), y=\(offset.y)", .debug)
        }

        if let opacity = mods.opacity {
            modifiedView = modifiedView.opacity(opacity)
        }

        switch mods.textSelection {
        case .enabled:
            modifiedView = modifiedView.textSelection(.enabled)
        case .disabled:
            modifiedView = modifiedView.textSelection(.disabled)
        case nil:
            break
        }

        if let degrees = mods.rotationDegrees {
            modifiedView = modifiedView.rotationEffect(.degrees(degrees))
        }

        if let scale = mods.scale {
            modifiedView = modifiedView.scaleEffect(x: scale.x, y: scale.y, anchor: resolveUnitPoint(scale.anchor))
        }

        switch mods.multilineTextAlignment {
        case .leading:
            modifiedView = modifiedView.multilineTextAlignment(.leading)
        case .center:
            modifiedView = modifiedView.multilineTextAlignment(.center)
        case .trailing:
            modifiedView = modifiedView.multilineTextAlignment(.trailing)
        case nil:
            break
        }

        if let zIndex = mods.zIndex {
            modifiedView = modifiedView.zIndex(zIndex)
        }

        if let border = mods.border {
            let color = ColorHelper.resolveColor(border.color) ?? .black
            modifiedView = modifiedView.border(color, width: border.width)
        }

        // Apply overlay modifier
        if let overlayElement = element.subviews?["overlay"] as? any ActionUIElementBase,
           let windowModel = ActionUIModel.shared.windowModels[windowUUID],
           let overlayModel = windowModel.viewModels[overlayElement.id] {
            let alignment = resolveAlignment(mods.overlayAlignment)
            modifiedView = modifiedView.overlay(alignment: alignment) {
                ActionUIView(element: overlayElement, model: overlayModel, windowUUID: windowUUID)
            }
        }

        // ignoresSafeArea: let this view extend into the safe area (e.g. a background under the
        // notch / home indicator). `true` ignores all regions on all edges; an object narrows
        // `edges` (top/bottom/leading/trailing/horizontal/vertical/all) and `regions`
        // (all/container/keyboard).
        if let safeArea = mods.ignoresSafeArea {
            modifiedView = AnyView(modifiedView).ignoresSafeArea(
                resolveSafeAreaRegions(safeArea.regions),
                edges: resolveSafeAreaEdges(safeArea.edges)
            )
        }

        // safeAreaInset: place a view in the safe area on an edge; the main content insets to
        // avoid it (SwiftUI's `.safeAreaInset(edge:alignment:spacing:)` - e.g. a bottom bar that
        // content scrolls clear of). The inset view's own properties parameterize it (safe-area-
        // specific names so they don't collide with a stack's own `spacing` / a swipe `edge`):
        // `safeAreaEdge` ("top"/"bottom"/"leading"/"trailing", default bottom), `safeAreaAlignment`,
        // `safeAreaSpacing`.
        if let insetElement = element.subviews?["safeAreaInset"] as? any ActionUIElementBase,
           let windowModel = ActionUIModel.shared.windowModels[windowUUID],
           let insetModel = windowModel.viewModels[insetElement.id] {
            let edge = (insetElement.properties["safeAreaEdge"] as? String) ?? "bottom"
            let spacing = insetElement.properties.cgFloat(forKey: "safeAreaSpacing")
            let alignName = insetElement.properties["safeAreaAlignment"] as? String
            let content = ActionUIView(element: insetElement, model: insetModel, windowUUID: windowUUID)
            switch edge {
            case "top", "bottom":
                let vEdge: VerticalEdge = (edge == "top") ? .top : .bottom
                modifiedView = AnyView(modifiedView).safeAreaInset(edge: vEdge, alignment: resolveSafeAreaHorizontalAlignment(alignName), spacing: spacing) { content }
            case "leading", "trailing":
                let hEdge: HorizontalEdge = (edge == "leading") ? .leading : .trailing
                modifiedView = AnyView(modifiedView).safeAreaInset(edge: hEdge, alignment: resolveSafeAreaVerticalAlignment(alignName), spacing: spacing) { content }
            default:
                modifiedView = AnyView(modifiedView).safeAreaInset(edge: .bottom, spacing: spacing) { content }
            }
        }

        switch mods.buttonStyle {
        case .plain:
            modifiedView = modifiedView.buttonStyle(.plain)
        case .bordered:
            modifiedView = modifiedView.buttonStyle(.bordered)
        case .borderless:
            modifiedView = modifiedView.buttonStyle(.borderless)
        case .borderedProminent:
            modifiedView = modifiedView.buttonStyle(.borderedProminent)
        case .automatic, nil:
            // automatic: no modifier, so a style inherited from a container stays in effect.
            break
        }

        switch mods.controlSize {
        case .mini:
            modifiedView = modifiedView.controlSize(.mini)
        case .small:
            modifiedView = modifiedView.controlSize(.small)
        case .regular:
            modifiedView = modifiedView.controlSize(.regular)
        case .large:
            modifiedView = modifiedView.controlSize(.large)
        case .extraLarge:
            modifiedView = modifiedView.controlSize(.extraLarge)
        case nil:
            break
        }

        if mods.labelsHidden {
            modifiedView = modifiedView.labelsHidden()
        }

        switch mods.scrollContentBackground {
        case .hidden:
            modifiedView = modifiedView.scrollContentBackground(.hidden)
        case .visible:
            modifiedView = modifiedView.scrollContentBackground(.visible)
        case .automatic, nil:
            // automatic: no modifier needed
            break
        }

        if let shadow = mods.shadow {
            let color = ColorHelper.resolveColor(shadow.color) ?? ColorHelper.defaultShadowColor
            modifiedView = modifiedView.shadow(color: color, radius: shadow.radius, x: shadow.x, y: shadow.y)
        }

        // hidden after everything drawn: the view's background, border, overlay, safe-area inset
        // and shadow hide with it, as on Web, Android and Linux. Applied earlier (it once came right
        // after disabled), a hidden view still drew the decoration applied after it. The modifiers
        // below draw nothing of their own.
        if mods.hidden {
            modifiedView = modifiedView.hidden()
        }

        // Apply animation (after all decorative modifiers; before behavioral/structural wrappers)
        if let animConfig = mods.animation {
            let anim = resolveAnimation(animConfig)
            let viewModel = ActionUIModel.shared.windowModels[windowUUID]?.viewModels[element.id]
            let watched = resolveAnimationWatchedValue(
                named: animConfig.watchedValue,
                mutationToken: viewModel?.mutationToken ?? 0,
                properties: properties,
                states: viewModel?.states ?? [:],
                viewValue: viewModel?.value
            )
            modifiedView = modifiedView.animation(anim, value: watched)
        }

        // Apply transition: how this view animates when inserted/removed at runtime. The transition
        // plays only inside an animated transaction; WindowModel.insertElement/removeElement wrap the
        // mutation in withAnimation when `transition` is declared (instant otherwise).
        if let transition = mods.transition {
            modifiedView = modifiedView.transition(resolveTransition(transition))
        }

        // Handle openURLActionID with .onOpenURL modifier
        if let openURLActionID = mods.openURLActionID {
            modifiedView = modifiedView.onOpenURL { url in
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(openURLActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: url)
                }
            }
        }

        // Handle onAppearActionID with .onAppear modifier
        if let onAppearActionID = mods.onAppearActionID {
            modifiedView = modifiedView.onAppear {
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(onAppearActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: nil)
                }
            }
        }

        // Handle onDisappearActionID with .onDisappear modifier
        if let onDisappearActionID = mods.onDisappearActionID {
            modifiedView = modifiedView.onDisappear {
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(onDisappearActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: nil)
                }
            }
        }

        // Handle onHoverActionID with .onHover modifier (macOS; silent no-op elsewhere)
#if os(macOS)
        if let onHoverActionID = mods.onHoverActionID {
            modifiedView = modifiedView.onHover { isHovering in
                Task { @MainActor in
                    ActionUIModel.shared.actionHandler(onHoverActionID, windowUUID: windowUUID, viewID: element.id, viewPartID: 0, context: ["isHovering": isHovering])
                }
            }
        }
#endif

        switch mods.columnWidth {
        case .range(let min, let ideal, let max):
            modifiedView = modifiedView.navigationSplitViewColumnWidth(
                min: min.map { CGFloat($0) },
                ideal: ideal,
                max: max.map { CGFloat($0) }
            )
        case .fixed(let width):
            modifiedView = modifiedView.navigationSplitViewColumnWidth(width)
        case nil:
            break
        }

        // Handle keyboardShortcut. The modifier set is already final: absent -> command; [] -> none.
        if let shortcut = mods.keyboardShortcut,
           let key = KeyName.parse(shortcut.key) {
            let keyEquivalent = KeyEquivalentHelper.keyEquivalent(for: key)
            var eventModifiers: EventModifiers = []
            for modifier in shortcut.modifiers {
                switch modifier {
                case .command:  eventModifiers.insert(.command)
                case .shift:    eventModifiers.insert(.shift)
                case .option:   eventModifiers.insert(.option)
                case .control:  eventModifiers.insert(.control)
                case .capslock: eventModifiers.insert(.capsLock)
                }
            }
            modifiedView = modifiedView.keyboardShortcut(keyEquivalent, modifiers: eventModifiers)
        }

        if let navigationTitle = mods.navigationTitle {
            modifiedView = modifiedView.navigationTitle(navigationTitle)
        }

        switch mods.titleDisplayMode {
        case .inline:
            modifiedView = modifiedView.toolbarTitleDisplayMode(.inline)
        case .large:
#if !os(macOS)
            modifiedView = modifiedView.toolbarTitleDisplayMode(.large)
#endif
        case .inlineLarge:
#if !os(macOS)
            modifiedView = modifiedView.toolbarTitleDisplayMode(.inlineLarge)
#endif
        case .automatic:
            modifiedView = modifiedView.toolbarTitleDisplayMode(.automatic)
        case nil:
            break
        }

        if let helpLabel = mods.help {
            modifiedView = AnyView(modifiedView).help(helpLabel)
        }

        // contextMenu: a long-press (iOS) / right-click (macOS) menu attached to this view.
        // Two subview slots, not a property array, because SwiftUI's
        // `.contextMenu(menuItems:preview:)` is itself two ViewBuilders: the `contextMenu`
        // array holds the menu's action items (real Button / Divider / Section elements,
        // each carrying its own title / systemImage / role / actionID), and the optional
        // `contextMenuPreview` is an arbitrary view shown above the menu - the only slot
        // where free-form layout / a big Image renders richly on iOS (macOS has no preview).
        if let menuItems = element.subviews?["contextMenu"] as? [any ActionUIElementBase], !menuItems.isEmpty {
            let items = ContextMenuMenuItems(items: menuItems, windowUUID: windowUUID)
#if os(macOS)
            // macOS right-click menus have no preview (the SwiftUI preview: variant is
            // unavailable there), so contextMenuPreview is ignored here - the native behavior.
            modifiedView = AnyView(modifiedView).contextMenu { items }
#else
            if let previewElement = element.subviews?["contextMenuPreview"] as? any ActionUIElementBase {
                let preview = ContextMenuPreviewContent(element: previewElement, windowUUID: windowUUID)
                modifiedView = AnyView(modifiedView).contextMenu { items } preview: { preview }
            } else {
                modifiedView = AnyView(modifiedView).contextMenu { items }
            }
#endif
        }

        // swipeActions: leading/trailing swipe-to-action Buttons on a List row - the
        // mobile delete/complete/flag idiom. Like contextMenu, a subview slot of real
        // Button elements (each carries its own title / systemImage / role / tint /
        // actionID); SwiftUI's `.swipeActions(edge:allowsFullSwipe:)` is a ViewBuilder
        // of Buttons. Each Button may declare `edge` ("leading"/"trailing", default
        // trailing); we partition by edge and call .swipeActions once per edge. A full
        // swipe triggers the first button of that edge, so `allowsFullSwipe` (default
        // true) is read from the first button declaring it on that edge. Honored only
        // inside a List - attached elsewhere it is a clean no-op, matching SwiftUI.
        if let swipeButtons = element.subviews?["swipeActions"] as? [any ActionUIElementBase], !swipeButtons.isEmpty {
            for edge in [HorizontalEdge.leading, HorizontalEdge.trailing] {
                let edgeName = (edge == .leading) ? "leading" : "trailing"
                let edgeButtons = swipeButtons.filter {
                    let declared = ($0.properties["edge"] as? String) ?? "trailing"
                    return declared == edgeName
                }
                guard !edgeButtons.isEmpty else { continue }
                let allowsFullSwipe = edgeButtons.compactMap { $0.properties["allowsFullSwipe"] as? Bool }.first ?? true
                let buttons = SwipeActionsButtons(items: edgeButtons, windowUUID: windowUUID)
                modifiedView = AnyView(modifiedView).swipeActions(edge: edge, allowsFullSwipe: allowsFullSwipe) { buttons }
            }
        }

        if let accessibilityLabel = mods.accessibilityLabel {
            modifiedView = AnyView(modifiedView).accessibilityLabel(accessibilityLabel)
        }

        if let accessibilityHint = mods.accessibilityHint {
            modifiedView = AnyView(modifiedView).accessibilityHint(accessibilityHint)
        }

        if let accessibilityHidden = mods.accessibilityHidden {
            modifiedView = AnyView(modifiedView).accessibilityHidden(accessibilityHidden)
        }

        if let accessibilityIdentifier = mods.accessibilityIdentifier {
            modifiedView = AnyView(modifiedView).accessibilityIdentifier(accessibilityIdentifier)
        }

        // Handle onDrop - requires a wrapper view for the isTargeted Binding and @State
        if let drop = mods.drop {
            modifiedView = DropModifierView(
                content: AnyView(modifiedView),
                onDropActionID: drop.actionID,
                onDropTypes: drop.types,
                onDropTargetedActionID: drop.targetedActionID,
                windowUUID: windowUUID,
                elementID: element.id
            )
        }

        // Apply this element's own "toolbar" as a SCREEN toolbar.
        //
        // screenToolbarItems returns nothing for a navigation container: a toolbar authored on a
        // NavigationStack or NavigationSplitView belongs to the CONTAINER, not to a screen, and
        // is a deprecated alias for "persistentToolbar". Those items are applied by the
        // container's own builder, which knows where each platform needs them (outside the
        // container on macOS, published to every screen elsewhere). Applying them here as well
        // would double them on macOS and misplace them elsewhere.
        let screenToolbarItems = ToolbarHelper.screenToolbarItems(of: element)
        if !screenToolbarItems.isEmpty {
            modifiedView = ToolbarModifierView(
                content: AnyView(modifiedView),
                toolbarItems: screenToolbarItems,
                windowUUID: windowUUID
            )
        }

        // Apply sheet modifier if the element has a sheet subview
        if let sheetElement = element.subviews?["sheet"] as? any ActionUIElementBase,
           let windowModel = ActionUIModel.shared.windowModels[windowUUID],
           let parentModel = windowModel.viewModels[element.id],
           let sheetModel = windowModel.viewModels[sheetElement.id] {
            modifiedView = SheetModifierView(
                content: AnyView(modifiedView),
                sheetElement: sheetElement,
                sheetModel: sheetModel,
                parentModel: parentModel,
                windowUUID: windowUUID,
                elementID: element.id,
                onDismissActionID: mods.sheetOnDismissActionID
            )
        }

        // Apply fullScreenCover modifier if the element has a fullScreenCover subview
        if let coverElement = element.subviews?["fullScreenCover"] as? any ActionUIElementBase,
           let windowModel = ActionUIModel.shared.windowModels[windowUUID],
           let parentModel = windowModel.viewModels[element.id],
           let coverModel = windowModel.viewModels[coverElement.id] {
            modifiedView = FullScreenCoverModifierView(
                content: AnyView(modifiedView),
                coverElement: coverElement,
                coverModel: coverModel,
                parentModel: parentModel,
                windowUUID: windowUUID,
                elementID: element.id,
                onDismissActionID: mods.fullScreenCoverOnDismissActionID
            )
        }

        // Apply searchable modifier: adds a search field to List / NavigationStack content.
        // The query is owned by SearchableModifierView and emitted to actionID on each change.
        if let searchable = mods.searchable {
            modifiedView = SearchableModifierView(
                content: AnyView(modifiedView),
                windowUUID: windowUUID,
                elementID: element.id,
                actionID: searchable.actionID,
                prompt: searchable.prompt
            )
        }

        // Apply popover modifier if the element has a popover subview
        if let popoverElement = element.subviews?["popover"] as? any ActionUIElementBase,
           let windowModel = ActionUIModel.shared.windowModels[windowUUID],
           let parentModel = windowModel.viewModels[element.id],
           let popoverModel = windowModel.viewModels[popoverElement.id] {
            return PopoverModifierView(
                content: AnyView(modifiedView),
                popoverElement: popoverElement,
                popoverModel: popoverModel,
                parentModel: parentModel,
                windowUUID: windowUUID,
                elementID: element.id,
                arrowEdge: resolveEdge(mods.popoverArrowEdge),
                popoverActionID: mods.popoverActionID,
                addTapGesture: element.type != "Button"
            )
        }

        return modifiedView
    }
}
