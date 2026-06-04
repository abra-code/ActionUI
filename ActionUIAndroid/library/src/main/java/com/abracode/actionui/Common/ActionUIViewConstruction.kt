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
 * Today only [STRING] has live consumers (TextField / SecureField / TextEditor).
 * [BOOLEAN]/[INT]/[DOUBLE] are defined ahead of Toggle / Slider / Stepper, the
 * controls the porting notes name as the next to land on this same bridge (see
 * `Private/Android_Porting_Notes.md`). The Apple-specific value types (Color,
 * Date, CLLocationCoordinate2D) and the List/Table content types ([String] /
 * [[String]]) are deferred with their elements.
 */
enum class ActionUIValueType {
    NONE,
    STRING,
    BOOLEAN,
    INT,
    DOUBLE,
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
}
