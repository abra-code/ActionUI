package com.abracode.actionui.Common

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

interface ActionUIElementBase {
    val id: Int
    val type: String
    val properties: JsonObject?
    val children: List<ActionUIElement>?
}

@Serializable
data class ActionUIElement(
    override val id: Int = 0,
    override val type: String = "",
    override val properties: JsonObject? = null,
    override val children: List<ActionUIElement>? = null
) : ActionUIElementBase
