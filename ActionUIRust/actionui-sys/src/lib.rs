// ActionUI - SwiftUI component library
// Copyright (c) 2025-2026 Tomasz Kukielka
//
// Licensed under the PolyForm Small Business License 1.0.0
// https://polyformproject.org/licenses/small-business/1.0.0

//! Raw declarations of the ActionUI C functions, and the link setup for the static
//! frameworks that implement them. No logic lives here; use the `actionui` crate.
//!
//! The declarations are written by hand, because the frameworks' generated headers
//! declare these functions only for Objective-C. `tests/declarations.rs` compares this
//! file with those headers and fails on any difference.
//!
//! Rules that hold for every function, unless its comment says otherwise:
//! - Strings are null-terminated UTF-8.
//! - A returned `*mut c_char` is owned by the caller and released with
//!   [`actionUIFreeString`]. A returned `*const c_char` is owned by ActionUI.
//! - Functions may be called from any thread; they move to the main thread themselves.
//!   Setters do so asynchronously, getters wait for the result.
//! - Callbacks are invoked on the main thread.

#![cfg(target_os = "macos")]
#![allow(non_snake_case)]

use std::ffi::{c_char, c_int, c_void};

// MARK: - Types (ActionUIC.h)

/// One of the `ACTIONUI_LOG_LEVEL_*` values.
pub type ActionUILogLevel = c_int;
pub const ACTIONUI_LOG_LEVEL_ERROR: ActionUILogLevel = 1;
pub const ACTIONUI_LOG_LEVEL_WARNING: ActionUILogLevel = 2;
pub const ACTIONUI_LOG_LEVEL_INFO: ActionUILogLevel = 3;
pub const ACTIONUI_LOG_LEVEL_DEBUG: ActionUILogLevel = 4;
pub const ACTIONUI_LOG_LEVEL_VERBOSE: ActionUILogLevel = 5;

/// One of the `ACTIONUI_MODAL_STYLE_*` values.
pub type ActionUIModalStyle = c_int;
pub const ACTIONUI_MODAL_STYLE_SHEET: ActionUIModalStyle = 0;
pub const ACTIONUI_MODAL_STYLE_FULL_SCREEN_COVER: ActionUIModalStyle = 1;

/// One of the `ACTIONUI_BUTTON_ROLE_*` values. Used inside the buttons JSON, as a number.
pub type ActionUIButtonRole = c_int;
pub const ACTIONUI_BUTTON_ROLE_DEFAULT: ActionUIButtonRole = 0;
pub const ACTIONUI_BUTTON_ROLE_CANCEL: ActionUIButtonRole = 1;
pub const ACTIONUI_BUTTON_ROLE_DESTRUCTIVE: ActionUIButtonRole = 2;

/// One of the `ACTIONUI_INSERT_POSITION_*` values.
pub type ActionUIInsertPosition = c_int;
pub const ACTIONUI_INSERT_POSITION_APPEND: ActionUIInsertPosition = 0;
pub const ACTIONUI_INSERT_POSITION_PREPEND: ActionUIInsertPosition = 1;
/// `positionParam` is the target index.
pub const ACTIONUI_INSERT_POSITION_AT: ActionUIInsertPosition = 2;
/// `positionParam` is the sibling's view ID. Flat containers only.
pub const ACTIONUI_INSERT_POSITION_BEFORE: ActionUIInsertPosition = 3;
/// `positionParam` is the sibling's view ID. Flat containers only.
pub const ACTIONUI_INSERT_POSITION_AFTER: ActionUIInsertPosition = 4;

/// Receives every log message: `(message, level)`.
pub type ActionUILoggerCallback = Option<unsafe extern "C" fn(*const c_char, ActionUILogLevel)>;

/// Receives an action: `(actionID, windowUUID, viewID, viewPartID, contextJSON)`.
/// `contextJSON` is null when the action carries no context. The strings are valid
/// only for the duration of the call.
pub type ActionUIActionHandler =
    Option<unsafe extern "C" fn(*const c_char, *const c_char, i64, i64, *const c_char)>;

// MARK: - Types (ActionUIApp.h)

pub type ActionUIAppLifecycleHandler = Option<unsafe extern "C" fn()>;

/// Returns true to allow termination, false to cancel it.
pub type ActionUIAppShouldTerminateHandler = Option<unsafe extern "C" fn() -> bool>;

/// Receives the UUID of the window the event is about.
pub type ActionUIAppWindowHandler = Option<unsafe extern "C" fn(*const c_char)>;

// MARK: - ActionUICAdapter

#[rustfmt::skip] // tests/declarations.rs reads one declaration per line
unsafe extern "C" {
    pub fn actionUIGetVersion() -> *mut c_char;
    pub fn actionUIFreeString(str: *mut c_char);

    pub fn actionUISetLogger(callback: ActionUILoggerCallback);
    pub fn actionUILog(message: *const c_char, level: ActionUILogLevel);

    pub fn actionUIGetLastError() -> *mut c_char;
    pub fn actionUIClearError();

    pub fn actionUIRegisterActionHandler(actionID: *const c_char, handler: ActionUIActionHandler) -> bool;
    pub fn actionUIUnregisterActionHandler(actionID: *const c_char) -> bool;
    pub fn actionUISetDefaultActionHandler(handler: ActionUIActionHandler);
    pub fn actionUIRemoveDefaultActionHandler();

    pub fn actionUISetElementValueJSON(windowUUID: *const c_char, viewID: i64, viewPartID: i64, valueJSON: *const c_char) -> bool;
    pub fn actionUIGetElementValueJSON(windowUUID: *const c_char, viewID: i64, viewPartID: i64) -> *mut c_char;
    pub fn actionUISetElementValueString(windowUUID: *const c_char, viewID: i64, viewPartID: i64, valueString: *const c_char, contentType: *const c_char) -> bool;
    pub fn actionUIGetElementValueString(windowUUID: *const c_char, viewID: i64, viewPartID: i64, contentType: *const c_char) -> *mut c_char;

    pub fn actionUISetIntValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, value: i64) -> bool;
    pub fn actionUISetDoubleValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, value: f64) -> bool;
    pub fn actionUISetBoolValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, value: bool) -> bool;
    pub fn actionUISetStringValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, value: *const c_char) -> bool;
    pub fn actionUIGetIntValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, outValue: *mut i64) -> bool;
    pub fn actionUIGetDoubleValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, outValue: *mut f64) -> bool;
    pub fn actionUIGetBoolValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64, outValue: *mut bool) -> bool;
    pub fn actionUIGetStringValue(windowUUID: *const c_char, viewID: i64, viewPartID: i64) -> *mut c_char;

    pub fn actionUIGetElementColumnCount(windowUUID: *const c_char, viewID: i64) -> i64;
    pub fn actionUIGetElementRowsJSON(windowUUID: *const c_char, viewID: i64) -> *mut c_char;
    pub fn actionUIClearElementRows(windowUUID: *const c_char, viewID: i64);
    pub fn actionUISetElementRowsJSON(windowUUID: *const c_char, viewID: i64, rowsJSON: *const c_char) -> bool;
    pub fn actionUIAppendElementRowsJSON(windowUUID: *const c_char, viewID: i64, rowsJSON: *const c_char) -> bool;

    pub fn actionUISelectElementRowByIndex(windowUUID: *const c_char, viewID: i64, index: i64) -> bool;
    pub fn actionUISelectElementRowWithContent(windowUUID: *const c_char, viewID: i64, text: *const c_char, column: i64) -> i64;
    pub fn actionUIClearElementSelection(windowUUID: *const c_char, viewID: i64);

    pub fn actionUIGetElementPropertyJSON(windowUUID: *const c_char, viewID: i64, propertyName: *const c_char) -> *mut c_char;
    pub fn actionUISetElementPropertyJSON(windowUUID: *const c_char, viewID: i64, propertyName: *const c_char, valueJSON: *const c_char) -> bool;

    pub fn actionUIGetElementStateJSON(windowUUID: *const c_char, viewID: i64, key: *const c_char) -> *mut c_char;
    pub fn actionUIGetElementStateString(windowUUID: *const c_char, viewID: i64, key: *const c_char) -> *mut c_char;
    pub fn actionUISetElementStateJSON(windowUUID: *const c_char, viewID: i64, key: *const c_char, valueJSON: *const c_char) -> bool;
    pub fn actionUISetElementStateFromString(windowUUID: *const c_char, viewID: i64, key: *const c_char, value: *const c_char) -> bool;

    pub fn actionUIGetElementInfoJSON(windowUUID: *const c_char) -> *mut c_char;

    /// Returns a retained `NSHostingController`; the caller owns it. For hosts that
    /// create their own windows. Main thread only.
    pub fn actionUILoadHostingControllerFromURL(urlString: *const c_char, windowUUID: *const c_char, isContentView: bool) -> *mut c_void;
    pub fn actionUIGetContentSizeLimits(windowUUID: *const c_char, outMinWidth: *mut f64, outMinHeight: *mut f64, outMaxWidth: *mut f64, outMaxHeight: *mut f64) -> bool;

    pub fn actionUIInsertElement(windowUUID: *const c_char, parentID: i64, json: *const c_char, container: *const c_char, position: ActionUIInsertPosition, positionParam: i64) -> i64;
    pub fn actionUIInsertRow(windowUUID: *const c_char, parentID: i64, json: *const c_char, container: *const c_char, position: ActionUIInsertPosition, positionParam: i64) -> *mut c_char;
    pub fn actionUIRemoveElement(windowUUID: *const c_char, viewID: i64) -> bool;

    pub fn actionUIPresentModal(windowUUID: *const c_char, jsonString: *const c_char, format: *const c_char, style: ActionUIModalStyle, onDismissActionID: *const c_char) -> bool;
    pub fn actionUIDismissModal(windowUUID: *const c_char);
    pub fn actionUIPresentAlert(windowUUID: *const c_char, title: *const c_char, message: *const c_char, buttonsJSON: *const c_char) -> bool;
    pub fn actionUIPresentConfirmationDialog(windowUUID: *const c_char, title: *const c_char, message: *const c_char, buttonsJSON: *const c_char) -> bool;
    pub fn actionUIDismissDialog(windowUUID: *const c_char);
    pub fn actionUIPresentToast(windowUUID: *const c_char, message: *const c_char, duration: f64, actionTitle: *const c_char, actionID: *const c_char) -> bool;
    pub fn actionUIDismissToast(windowUUID: *const c_char);
}

// MARK: - ActionUIAppKitApplication

#[rustfmt::skip] // tests/declarations.rs reads one declaration per line
unsafe extern "C" {
    pub fn actionUIAppSetWillFinishLaunchingHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetDidFinishLaunchingHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetWillBecomeActiveHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetDidBecomeActiveHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetWillResignActiveHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetDidResignActiveHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetWillTerminateHandler(handler: ActionUIAppLifecycleHandler);
    pub fn actionUIAppSetShouldTerminateHandler(handler: ActionUIAppShouldTerminateHandler);
    pub fn actionUIAppSetWindowWillCloseHandler(handler: ActionUIAppWindowHandler);
    pub fn actionUIAppSetWindowWillPresentHandler(handler: ActionUIAppWindowHandler);

    pub fn actionUIAppSetName(name: *const c_char);
    pub fn actionUIAppSetIcon(path: *const c_char);

    /// Runs the application until it terminates. Main thread only.
    pub fn actionUIAppRun();
    pub fn actionUIAppTerminate();

    pub fn actionUIAppLoadAndPresentWindow(urlString: *const c_char, windowUUID: *const c_char, title: *const c_char);
    pub fn actionUIAppCloseWindow(windowUUID: *const c_char);

    pub fn actionUIAppRunAlert(configJSON: *const c_char) -> *mut c_char;
    pub fn actionUIAppRunOpenPanel(configJSON: *const c_char) -> *mut c_char;
    pub fn actionUIAppRunSavePanel(configJSON: *const c_char) -> *mut c_char;

    pub fn actionUIAppLoadMenuBar(jsonString: *const c_char);

    pub fn actionUIAppStartRemoteServer(socketPath: *const c_char) -> bool;
    pub fn actionUIAppStopRemoteServer();
    pub fn actionUIAppRemoteServerToken() -> *const c_char;
    pub fn actionUIAppRemoteCopyServerToken(outToken: *mut c_char, outTokenSize: isize) -> bool;
    pub fn actionUIAppRemoteServerEndpoint() -> *const c_char;
}

// MARK: - ActionUIRemote

#[rustfmt::skip] // tests/declarations.rs reads one declaration per line
unsafe extern "C" {
    pub fn actionUIRemoteStartServer(socketPath: *const c_char, hostName: *const c_char, hostVersion: *const c_char) -> bool;
    pub fn actionUIRemoteStopServer();
    pub fn actionUIRemoteServerIsRunning() -> bool;
    pub fn actionUIRemoteServerEndpoint() -> *const c_char;
    pub fn actionUIRemoteServerToken() -> *const c_char;
    pub fn actionUIRemoteCopyServerToken(outToken: *mut c_char, outTokenSize: isize) -> bool;
    pub fn actionUIRemoteMintToken(label: *const c_char, outToken: *mut c_char, outTokenSize: isize) -> bool;
    pub fn actionUIRemoteAddToken(token: *const c_char, label: *const c_char) -> bool;
    pub fn actionUIRemoteRevokeTokensWithLabel(label: *const c_char);
    pub fn actionUIRemoteSetRequiresToken(required: bool) -> bool;
    pub fn actionUIRemoteUnexportToken() -> bool;
}
