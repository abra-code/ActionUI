package com.abracode.actionui.Common

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier

/**
 * The value type an element exposes through the programmatic value bridge
 * (`ActionUIModel.get/setElementValue[FromString]`). The Android analog of the
 * Swift `ActionUIElementConstruction.valueType` (`Any.Type`), narrowed to an
 * enum because Kotlin has no lightweight `Any.Type` comparison and the live set
 * of value-bearing controls is small.
 *
 * [NONE] is the analog of Swift's `Void.self` - a display/container element with
 * no value (Text, the stacks, the shapes, Image). Only elements that declare a
 * non-[NONE] type get a seeded initial value and can be read/written by string.
 *
 * Live consumers: [STRING] (TextField / SecureField / TextEditor /
 * ContentUnavailableView), [BOOLEAN] (Toggle), [INT]/[DOUBLE] (Slider / Stepper),
 * and the value-bridge-extension (B6) types below.
 *
 * The B6 types add the Apple value types that several controls need:
 *   * [DATE] - `DatePicker`. Carried as a `java.time.LocalDate` (date-only,
 *     timezone-free, matching Apple's `.withFullDate` serialization); see
 *     `Helpers/DateHelper.kt`.
 *   * [COLOR] - `ColorPicker`. Carried as a Compose
 *     `androidx.compose.ui.graphics.Color`; parsed/serialized by
 *     `Helpers/ColorHelper.kt`.
 *   * [STRING_LIST] - the `List` (and, on Apple, `Table`) **selection** value:
 *     the selected row's columns as a `List<String>` (empty when nothing is
 *     selected). Mirrors Apple's `[String]`.
 *   * [COORDINATE] - `Map`. Carried as a
 *     [com.abracode.actionui.Helpers.ActionUICoordinate] (latitude/longitude
 *     degrees, the analog of Apple's `CLLocationCoordinate2D`);
 *     parsed/serialized to the canonical `{"latitude": N, "longitude": N}`
 *     JSON string by `Helpers/CoordinateHelper.kt`, matching Apple's
 *     `Map.parseStringValue`/`serializeValueToString`.
 *
 * Apple's `[[String]]` Table-content value has no live Android consumer
 * (`Table` is a macOS-only no-op) and is deferred with that element.
 */
enum class ActionUIValueType {
    NONE,
    STRING,
    BOOLEAN,
    INT,
    DOUBLE,
    DATE,
    COLOR,
    STRING_LIST,
    COORDINATE,
}

interface ActionUIViewConstruction {
    @Composable
    fun BuildView(element: ActionUIElement, modifier: Modifier)

    /**
     * The type of value this element exposes through the value bridge. Defaults
     * to [ActionUIValueType.NONE] so display/container elements need not opt in,
     * matching Swift's default `valueType = Void.self`.
     */
    val valueType: ActionUIValueType
        get() = ActionUIValueType.NONE

    /**
     * The value to seed into the element's [ViewModel] when the window is first
     * populated, derived from the element's JSON properties. The Android analog
     * of Swift's `ActionUIElementConstruction.initialValue`. Default `null`;
     * value-bearing elements override it (e.g. a text control returns its
     * initial string). Only consulted when [valueType] is not
     * [ActionUIValueType.NONE].
     */
    fun initialValue(element: ActionUIElement): Any? = null

    /**
     * The view-specific state to seed into the element's [ViewModel.states] when
     * the window is first populated, derived from the element's JSON properties.
     * The Android analog of Swift's `ActionUIElementConstruction.initialStates`.
     * Default empty; elements with observable state override it (e.g.
     * `DisclosureGroup` returns its initial `isExpanded`). Seeded by
     * [WindowModel.populateViewModels] so the state is host-addressable through
     * the element state API before any user interaction.
     */
    fun initialStates(element: ActionUIElement): Map<String, Any> = emptyMap()

    /**
     * The named subview containers this element accepts runtime insertions into,
     * each mapped to its [ContainerShape]. The Android analog of Swift's
     * `ActionUIElementConstruction.insertableContainers`. Default `null` (no
     * insertions), so leaf and single-child elements need not opt in.
     *
     * A container of shape [ContainerShape.FLAT] (`children` / `destinations`)
     * accepts [ActionUIModel.insertElement]; [ContainerShape.ROWS] (`Grid`'s
     * `rows`) accepts [ActionUIModel.insertRow]. The mutation engine
     * ([WindowModel]) writes the new container contents into the parent
     * [ViewModel.dynamicSubviews], which the shared build entry point
     * (`Helpers/ViewModifierHelper.kt`) merges back over the element each
     * recomposition - so the declaring view's existing `element.children` /
     * `element.destinations` / `element.rows` read picks up the live state with
     * no per-view wiring (the declarative-Compose advantage over the web port,
     * which needs imperative bindings).
     *
     * Only declare a container the builder actually renders from the matching
     * field. The single-child `content` family (`GroupBox` / `DisclosureGroup` /
     * `LabeledContent` render `children` as an array on Android, so they do
     * declare `children`); `ToolbarItemGroup` is rendered by the toolbar host,
     * not the normal child loop, and is deferred with the toolbar track.
     */
    val insertableContainers: Map<String, ContainerShape>?
        get() = null
}
