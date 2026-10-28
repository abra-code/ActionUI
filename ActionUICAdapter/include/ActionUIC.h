// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//
//  ActionUIC.h
//  ActionUICAdapter
//
//  C interface for ActionUI, enabling integration with C-based languages.
//  Part of the ActionUI project - provides a dynamic framework for C bindings.
//
//  The types (enums, callback typedefs) and a prototype for every function, so plain C
//  clients can call ActionUI. The Swift compiler also declares the @c functions, in
//  ActionUICAdapter-Swift.h. The two declarations must agree: HeaderCheck/ActionUICHeaderCheck.c
//  includes both, so a differing type fails the build, and Scripts/check-c-prototypes.sh
//  checks that every function has a prototype here.
//
//  Bool types: the functions use Swift's CBool (= C stdbool.h bool) for all boolean
//  parameters and return values; the generated header emits `bool`.
//

#ifndef ActionUIC_h
#define ActionUIC_h

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// MARK: - Logging

/// Log levels matching ActionUI.LoggerLevel
typedef enum {
    ActionUILogLevelError   = 1,
    ActionUILogLevelWarning = 2,
    ActionUILogLevelInfo    = 3,
    ActionUILogLevelDebug   = 4,
    ActionUILogLevelVerbose = 5
} ActionUILogLevel;

/// Logger callback function type.
/// Parameters: message (null-terminated UTF-8 C string), level
typedef void (*ActionUILoggerCallback)(const char* message, ActionUILogLevel level);

// MARK: - Action Handling

/// Action handler callback function type.
/// Parameters: actionID, windowUUID, viewID, viewPartID, contextJSON (nullable)
typedef void (*ActionUIActionHandler)(const char* actionID,
                                      const char* windowUUID,
                                      int64_t     viewID,
                                      int64_t     viewPartID,
                                      const char* contextJSON);

// MARK: - Modal Presentation

/// Modal presentation style.
typedef enum {
    ActionUIModalStyleSheet           = 0,
    ActionUIModalStyleFullScreenCover = 1
} ActionUIModalStyle;

/// Button role for dialog buttons.
typedef enum {
    ActionUIButtonRoleDefault     = 0,  ///< Normal prominence (no special role)
    ActionUIButtonRoleCancel      = 1,  ///< Cancel action
    ActionUIButtonRoleDestructive = 2   ///< Destructive action (red tint)
} ActionUIButtonRole;

// MARK: - Runtime Structural Mutations

/// Insert position for actionUIInsertElement / actionUIInsertRow.
/// Pass positionParam = 0 for Append and Prepend.
/// For At, positionParam is the target index.
/// For Before/After, positionParam is the sibling's viewID.
/// Before and After are invalid for row containers — use Append, Prepend, or At.
typedef enum {
    ActionUIInsertPositionAppend  = 0,  ///< Append to the end of the container
    ActionUIInsertPositionPrepend = 1,  ///< Prepend to the beginning of the container
    ActionUIInsertPositionAt      = 2,  ///< Insert at positionParam index
    ActionUIInsertPositionBefore  = 3,  ///< Insert before the sibling with positionParam id (flat containers only)
    ActionUIInsertPositionAfter   = 4   ///< Insert after the sibling with positionParam id (flat containers only)
} ActionUIInsertPosition;

// The Swift-generated declarations are noexcept in C++, so these are too: a C++ or
// Objective-C++ client that includes both would otherwise see conflicting declarations.
#ifndef ACTIONUI_NOEXCEPT
#  if defined(__cplusplus) && __cplusplus >= 201103L
#    define ACTIONUI_NOEXCEPT noexcept
#  else
#    define ACTIONUI_NOEXCEPT
#  endif
#endif

// MARK: - Functions
//
// Strings are null-terminated UTF-8. A returned `char *` is the caller's: free it with
// actionUIFreeString. NULL is allowed only where a parameter is marked "may be NULL"; a NULL
// return means failure or nothing found, and actionUIGetLastError says which.

// Library, errors and logging
char *actionUIGetVersion(void) ACTIONUI_NOEXCEPT;  // ActionUI's version, such as "0.9.0"
char *actionUIGetLastError(void) ACTIONUI_NOEXCEPT;
void actionUIClearError(void) ACTIONUI_NOEXCEPT;
void actionUIFreeString(char *str) ACTIONUI_NOEXCEPT;
void actionUISetLogger(ActionUILoggerCallback callback) ACTIONUI_NOEXCEPT;  // callback may be NULL
void actionUILog(const char *message, ActionUILogLevel level) ACTIONUI_NOEXCEPT;

// Action handlers
bool actionUIRegisterActionHandler(const char *actionID, ActionUIActionHandler handler) ACTIONUI_NOEXCEPT;
bool actionUIUnregisterActionHandler(const char *actionID) ACTIONUI_NOEXCEPT;
void actionUISetDefaultActionHandler(ActionUIActionHandler handler) ACTIONUI_NOEXCEPT;  // handler may be NULL
void actionUIRemoveDefaultActionHandler(void) ACTIONUI_NOEXCEPT;

// Element values
bool actionUISetElementValueJSON(const char *windowUUID, int64_t viewID, int64_t viewPartID, const char *valueJSON) ACTIONUI_NOEXCEPT;
char *actionUIGetElementValueJSON(const char *windowUUID, int64_t viewID, int64_t viewPartID) ACTIONUI_NOEXCEPT;
bool actionUISetElementValueString(const char *windowUUID, int64_t viewID, int64_t viewPartID, const char *valueString, const char *contentType) ACTIONUI_NOEXCEPT;  // contentType may be NULL
char *actionUIGetElementValueString(const char *windowUUID, int64_t viewID, int64_t viewPartID, const char *contentType) ACTIONUI_NOEXCEPT;  // contentType may be NULL
bool actionUISetIntValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, int64_t value) ACTIONUI_NOEXCEPT;
bool actionUIGetIntValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, int64_t *outValue) ACTIONUI_NOEXCEPT;
bool actionUISetDoubleValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, double value) ACTIONUI_NOEXCEPT;
bool actionUIGetDoubleValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, double *outValue) ACTIONUI_NOEXCEPT;
bool actionUISetBoolValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, bool value) ACTIONUI_NOEXCEPT;
bool actionUIGetBoolValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, bool *outValue) ACTIONUI_NOEXCEPT;
bool actionUISetStringValue(const char *windowUUID, int64_t viewID, int64_t viewPartID, const char *value) ACTIONUI_NOEXCEPT;
char *actionUIGetStringValue(const char *windowUUID, int64_t viewID, int64_t viewPartID) ACTIONUI_NOEXCEPT;

// Properties, states and element info
bool actionUISetElementPropertyJSON(const char *windowUUID, int64_t viewID, const char *propertyName, const char *valueJSON) ACTIONUI_NOEXCEPT;
char *actionUIGetElementPropertyJSON(const char *windowUUID, int64_t viewID, const char *propertyName) ACTIONUI_NOEXCEPT;
bool actionUISetElementStateJSON(const char *windowUUID, int64_t viewID, const char *key, const char *valueJSON) ACTIONUI_NOEXCEPT;
char *actionUIGetElementStateJSON(const char *windowUUID, int64_t viewID, const char *key) ACTIONUI_NOEXCEPT;
bool actionUISetElementStateFromString(const char *windowUUID, int64_t viewID, const char *key, const char *value) ACTIONUI_NOEXCEPT;
char *actionUIGetElementStateString(const char *windowUUID, int64_t viewID, const char *key) ACTIONUI_NOEXCEPT;
char *actionUIGetElementInfoJSON(const char *windowUUID) ACTIONUI_NOEXCEPT;

// Windows
void actionUIRemoveWindow(const char *windowUUID) ACTIONUI_NOEXCEPT;  // forgets a closed window's model

// Rows and selection (Table, List)
bool actionUISetElementRowsJSON(const char *windowUUID, int64_t viewID, const char *rowsJSON) ACTIONUI_NOEXCEPT;
bool actionUIAppendElementRowsJSON(const char *windowUUID, int64_t viewID, const char *rowsJSON) ACTIONUI_NOEXCEPT;
char *actionUIGetElementRowsJSON(const char *windowUUID, int64_t viewID) ACTIONUI_NOEXCEPT;
void actionUIClearElementRows(const char *windowUUID, int64_t viewID) ACTIONUI_NOEXCEPT;
int64_t actionUIGetElementColumnCount(const char *windowUUID, int64_t viewID) ACTIONUI_NOEXCEPT;
bool actionUISelectElementRowByIndex(const char *windowUUID, int64_t viewID, int64_t index) ACTIONUI_NOEXCEPT;
int64_t actionUISelectElementRowWithContent(const char *windowUUID, int64_t viewID, const char *text, int64_t column) ACTIONUI_NOEXCEPT;
void actionUIClearElementSelection(const char *windowUUID, int64_t viewID) ACTIONUI_NOEXCEPT;

// Structural mutations
int64_t actionUIInsertElement(const char *windowUUID, int64_t parentID, const char *json, const char *container, ActionUIInsertPosition position, int64_t positionParam) ACTIONUI_NOEXCEPT;  // container may be NULL; returns -1 on failure
char *actionUIInsertRow(const char *windowUUID, int64_t parentID, const char *json, const char *container, ActionUIInsertPosition position, int64_t positionParam) ACTIONUI_NOEXCEPT;  // container may be NULL
bool actionUIRemoveElement(const char *windowUUID, int64_t viewID) ACTIONUI_NOEXCEPT;

// Modals, dialogs and toasts
bool actionUIPresentModal(const char *windowUUID, const char *jsonString, const char *format, ActionUIModalStyle style, const char *onDismissActionID) ACTIONUI_NOEXCEPT;  // onDismissActionID may be NULL
void actionUIDismissModal(const char *windowUUID) ACTIONUI_NOEXCEPT;
bool actionUIPresentAlert(const char *windowUUID, const char *title, const char *message, const char *buttonsJSON) ACTIONUI_NOEXCEPT;  // message and buttonsJSON may be NULL
bool actionUIPresentConfirmationDialog(const char *windowUUID, const char *title, const char *message, const char *buttonsJSON) ACTIONUI_NOEXCEPT;  // message may be NULL
void actionUIDismissDialog(const char *windowUUID) ACTIONUI_NOEXCEPT;
bool actionUIPresentToast(const char *windowUUID, const char *message, double duration, const char *actionTitle, const char *actionID) ACTIONUI_NOEXCEPT;  // actionTitle and actionID may be NULL
void actionUIDismissToast(const char *windowUUID) ACTIONUI_NOEXCEPT;

// Apple only (ActionUIC+Apple.swift): a build for another platform has no such functions.
#if defined(__APPLE__)
void *actionUILoadHostingControllerFromURL(const char *urlString, const char *windowUUID, bool isContentView) ACTIONUI_NOEXCEPT;  // NSHostingController on macOS, UIView on iOS; retained
bool actionUIGetContentSizeLimits(const char *windowUUID, double *outMinWidth, double *outMinHeight, double *outMaxWidth, double *outMaxHeight) ACTIONUI_NOEXCEPT;  // macOS; any out pointer may be NULL
#endif

#ifdef __cplusplus
}
#endif

#endif /* ActionUIC_h */
