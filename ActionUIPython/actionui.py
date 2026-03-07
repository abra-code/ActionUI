"""
ActionUI Python Module
Native macOS GUI framework using ActionUI via C extension.

This module provides a Pythonic interface over the native C extension
(_actionui).  All heavy lifting — type conversion, JSON
serialisation, and GIL management — is handled in the C layer.
"""

import _actionui
import json
import uuid
from typing import Optional, Callable, Any, Dict, List
from enum import IntEnum
from dataclasses import dataclass


class LogLevel(IntEnum):
    """Log levels for ActionUI.  Values match ActionUILogLevel in ActionUIC.h."""
    ERROR   = _actionui.LOG_ERROR
    WARNING = _actionui.LOG_WARNING
    INFO    = _actionui.LOG_INFO
    DEBUG   = _actionui.LOG_DEBUG
    VERBOSE = _actionui.LOG_VERBOSE


class ActionUIError(Exception):
    """Base exception for ActionUI errors."""
    pass


@dataclass
class ActionContext:
    """Context information passed to action handlers."""
    action_id:    str
    window_uuid:  str
    view_id:      int
    view_part_id: int
    context:      Optional[Any] = None


class Logger:
    """Logger for ActionUI messages."""

    def __init__(self):
        self._callback: Optional[Callable[[str, LogLevel], None]] = None
        _actionui.set_logger(self._log_callback)

    def _log_callback(self, message: str, level: int):
        if self._callback:
            self._callback(message, LogLevel(level))
        else:
            print(f"[ActionUI][{LogLevel(level).name}] {message}")

    def set_callback(self, callback: Optional[Callable[[str, LogLevel], None]]):
        """Set (or clear) a custom logging callback."""
        self._callback = callback


class Application:
    """Main application class managing windows and actions."""

    _instance: Optional['Application'] = None

    def __init__(self, name: Optional[str] = None, icon: Optional[str] = None):
        """Create the application singleton.

        Args:
            name: Application name shown in the menu bar (About, Hide, Quit).
                  Defaults to the process name if ``None``.
            icon: Path to an image file (PNG, ICNS, etc.) used as the
                  application icon in the Dock and About panel.  If ``None``,
                  the default ActionUI icon shipped alongside this module is
                  used automatically.
        """
        if Application._instance is not None:
            raise RuntimeError("Only one Application instance can exist")

        Application._instance = self
        self._action_handlers: Dict[str, Callable[[ActionContext], None]] = {}
        self._default_handler: Optional[Callable[[ActionContext], None]] = None
        self.logger = Logger()
        # Keeps Python references to lifecycle callbacks so the GC cannot
        # collect them while they are registered in the C layer.
        self._lifecycle_callbacks: Dict[str, Optional[Callable]] = {}
        self._window_close_handler: Optional[Callable[['Window'], None]] = None
        self._window_present_handler: Optional[Callable[['Window'], None]] = None
        # UUID → Window for all windows opened via load_and_present_window().
        self._windows: Dict[str, 'Window'] = {}

        if name is not None:
            _actionui.app_set_name(name)

        import os
        if icon is not None:
            _actionui.app_set_icon(os.path.abspath(icon))
        else:
            default_icon = os.path.join(os.path.dirname(__file__), "actionui-app-icon.icns")
            if os.path.isfile(default_icon):
                _actionui.app_set_icon(default_icon)

        _actionui.set_default_action_handler(self._action_bridge)
        # Register internal bridges so we always handle window lifecycle
        # events regardless of whether the user registers their own handlers.
        _actionui.app_set_window_will_close(self._on_window_will_close)
        _actionui.app_set_window_will_present(self._on_window_will_present)

    @classmethod
    def instance(cls) -> Optional['Application']:
        return cls._instance

    # ------------------------------------------------------------------
    # Action handling
    # ------------------------------------------------------------------

    def _action_bridge(self, action_id: str, window_uuid: str,
                        view_id: int, view_part_id: int,
                        context_json: Optional[str]):
        context = None
        if context_json:
            try:
                context = json.loads(context_json)
            except json.JSONDecodeError:
                context = context_json

        ctx = ActionContext(
            action_id=action_id,
            window_uuid=window_uuid,
            view_id=view_id,
            view_part_id=view_part_id,
            context=context,
        )

        handler = self._action_handlers.get(action_id, self._default_handler)
        if handler:
            try:
                handler(ctx)
            except Exception as e:
                import traceback
                print(f"Error in action handler '{action_id}': {e}")
                traceback.print_exc()
        else:
            print(f"No handler registered for action: {action_id}")

    def action(self, action_id: str) -> Callable:
        """
        Decorator that registers a function as an action handler.

        Example::

            @app.action("button.click")
            def on_click(ctx: ActionContext):
                print(f"Button {ctx.view_id} clicked!")
        """
        def decorator(func: Callable[[ActionContext], None]):
            self.register_handler(action_id, func)
            return func
        return decorator

    def register_handler(self, action_id: str, handler: Callable[[ActionContext], None]):
        self._action_handlers[action_id] = handler
        _actionui.register_action_handler(action_id, self._action_bridge)

    def unregister_handler(self, action_id: str):
        self._action_handlers.pop(action_id, None)
        _actionui.unregister_action_handler(action_id)

    def set_default_handler(self, handler: Optional[Callable[[ActionContext], None]]):
        self._default_handler = handler

    # ------------------------------------------------------------------
    # App lifecycle — internal helpers
    # ------------------------------------------------------------------

    def _register_lifecycle(self, name: str, setter, func: Optional[Callable]):
        """Store *func* in Python (preventing GC) and register with the C layer."""
        self._lifecycle_callbacks[name] = func
        setter(func)

    def _on_window_will_close(self, window_uuid: str):
        """Internal bridge: clean up tracked window, then call user handler."""
        window = self._windows.pop(window_uuid, None) or Window(window_uuid)
        if self._window_close_handler:
            try:
                self._window_close_handler(window)
            except Exception as e:
                import traceback
                print(f"Error in window_will_close handler: {e}")
                traceback.print_exc()

    def _on_window_will_present(self, window_uuid: str):
        """Internal bridge: call user handler with the Window before it's shown."""
        if self._window_present_handler:
            window = self._windows.get(window_uuid) or Window(window_uuid)
            try:
                self._window_present_handler(window)
            except Exception as e:
                import traceback
                print(f"Error in window_will_present handler: {e}")
                traceback.print_exc()

    # ------------------------------------------------------------------
    # App lifecycle — decorator API
    # ------------------------------------------------------------------

    def will_finish_launching(self, func: Callable[[], None]) -> Callable:
        """Decorator: called just before the application finishes launching."""
        self._register_lifecycle('will_finish_launching',
                                 _actionui.app_set_will_finish_launching, func)
        return func

    def did_finish_launching(self, func: Callable[[], None]) -> Callable:
        """Decorator: called after the application has finished launching."""
        self._register_lifecycle('did_finish_launching',
                                 _actionui.app_set_did_finish_launching, func)
        return func

    def will_become_active(self, func: Callable[[], None]) -> Callable:
        """Decorator: called when the application is about to become active."""
        self._register_lifecycle('will_become_active',
                                 _actionui.app_set_will_become_active, func)
        return func

    def did_become_active(self, func: Callable[[], None]) -> Callable:
        """Decorator: called after the application has become active."""
        self._register_lifecycle('did_become_active',
                                 _actionui.app_set_did_become_active, func)
        return func

    def will_resign_active(self, func: Callable[[], None]) -> Callable:
        """Decorator: called when the application is about to resign active status."""
        self._register_lifecycle('will_resign_active',
                                 _actionui.app_set_will_resign_active, func)
        return func

    def did_resign_active(self, func: Callable[[], None]) -> Callable:
        """Decorator: called after the application has resigned active status."""
        self._register_lifecycle('did_resign_active',
                                 _actionui.app_set_did_resign_active, func)
        return func

    def will_terminate(self, func: Callable[[], None]) -> Callable:
        """Decorator: called when the application is about to terminate."""
        self._register_lifecycle('will_terminate',
                                 _actionui.app_set_will_terminate, func)
        return func

    def should_terminate(self, func: Callable[[], bool]) -> Callable:
        """
        Decorator: called when the application receives a termination request.

        The decorated function must return ``True`` to allow termination or
        ``False`` to cancel it.

        Example::

            @app.should_terminate
            def on_should_terminate() -> bool:
                return confirm_quit_dialog()
        """
        self._register_lifecycle('should_terminate',
                                 _actionui.app_set_should_terminate, func)
        return func

    def window_will_close(self, func: Callable[['Window'], None]) -> Callable:
        """
        Decorator: called when a tracked window is about to close.

        The decorated function receives the :class:`Window` object as its only
        argument.  Window cleanup (removing from the internal registry) always
        happens before this handler is invoked.

        Example::

            @app.window_will_close
            def on_close(window: Window):
                print(f"Window {window.uuid} closed")
        """
        self._window_close_handler = func
        return func

    def window_will_present(self, func: Callable[['Window'], None]) -> Callable:
        """
        Decorator: called right before a new window is presented on screen.

        Fires synchronously before ``makeKeyAndOrderFront``, so values and
        states set here are applied before the first frame renders.  The
        decorated function receives the :class:`Window` object as its only
        argument.

        Example::

            @app.window_will_present
            def on_present(window: Window):
                window.set_string(1, "Hello")
                window.set_bool(2, True)
        """
        self._window_present_handler = func
        return func

    # ------------------------------------------------------------------
    # App control
    # ------------------------------------------------------------------

    def run(self):
        """Start the NSApplication run loop.  Blocks until the app terminates.

        This must be the last call in the script.  All setup (action handlers,
        lifecycle callbacks, initial window creation via ``did_finish_launching``)
        must be configured before calling ``run()``.
        """
        _actionui.app_run()

    def terminate(self):
        """Request graceful termination (equivalent to Cmd-Q)."""
        _actionui.app_terminate()

    def load_and_present_window(self,
                                url: str,
                                window_uuid: Optional[str] = None,
                                title: Optional[str] = None) -> 'Window':
        """Load an ActionUI JSON view from *url* and present it in a new window.

        Args:
            url:         ``file://``, ``http://``, or ``https://`` URL of the
                         ActionUI JSON definition.  A bare filesystem path is
                         accepted and automatically converted to a
                         ``file://`` URL.
            window_uuid: Caller-supplied UUID; generated automatically if
                         ``None``.
            title:       Window title; derived from the URL filename if ``None``.

        Returns:
            A :class:`Window` instance bound to the new window.  The window is
            tracked internally and removed from the registry when it closes.
        """
        if window_uuid is None:
            window_uuid = str(uuid.uuid4())
        if not url.startswith(('file://', 'http://', 'https://')):
            import os
            url = 'file://' + os.path.abspath(url)
        # Create and register the Window before calling into C so that it is
        # available inside the window_will_present callback, which fires
        # synchronously before makeKeyAndOrderFront.
        window = Window(window_uuid)
        self._windows[window_uuid] = window
        _actionui.app_load_and_present_window(url, window_uuid, title)
        return window

    def close_window(self, window_uuid: str):
        """Close the window identified by *window_uuid*.

        The ``window_will_close`` handler fires before the window is removed
        from the internal registry.
        """
        _actionui.app_close_window(window_uuid)

    # ------------------------------------------------------------------
    # File panels (NSOpenPanel / NSSavePanel)
    # ------------------------------------------------------------------

    def open_panel(self, *,
                   title: Optional[str] = None,
                   prompt: Optional[str] = None,
                   message: Optional[str] = None,
                   identifier: Optional[str] = None,
                   allowed_types: Optional[List[str]] = None,
                   allows_multiple: bool = False,
                   can_choose_files: bool = True,
                   can_choose_directories: bool = False,
                   directory: Optional[str] = None,
                   shows_hidden_files: bool = False,
                   treats_file_packages_as_directories: bool = False,
                   can_create_directories: bool = True,
                   allows_other_file_types: bool = False) -> Optional[List[str]]:
        """Run an NSOpenPanel.  Returns a list of selected file paths, or
        ``None`` if the user cancelled.

        All parameters are optional; sensible defaults are applied.
        ``allowed_types`` accepts file extensions (``"json"``) and/or
        UTI strings (``"public.image"``).

        Must be called while the run loop is active (e.g. from an action
        handler or lifecycle callback).
        """
        config = self._build_panel_config(
            title=title, prompt=prompt, message=message,
            identifier=identifier, allowed_types=allowed_types,
            directory=directory, shows_hidden_files=shows_hidden_files,
            treats_file_packages_as_directories=treats_file_packages_as_directories,
            can_create_directories=can_create_directories,
            allows_other_file_types=allows_other_file_types,
        )
        if allows_multiple:
            config["allowsMultipleSelection"] = True
        if not can_choose_files:
            config["canChooseFiles"] = False
        if can_choose_directories:
            config["canChooseDirectories"] = True

        config_json = json.dumps(config) if config else None
        result = _actionui.app_run_open_panel(config_json)
        if result is None:
            return None
        return json.loads(result)

    def save_panel(self, *,
                   title: Optional[str] = None,
                   prompt: Optional[str] = None,
                   message: Optional[str] = None,
                   identifier: Optional[str] = None,
                   allowed_types: Optional[List[str]] = None,
                   filename: Optional[str] = None,
                   directory: Optional[str] = None,
                   shows_hidden_files: bool = False,
                   treats_file_packages_as_directories: bool = False,
                   can_create_directories: bool = True,
                   allows_other_file_types: bool = False) -> Optional[str]:
        """Run an NSSavePanel.  Returns the chosen file path, or ``None``
        if the user cancelled.

        All parameters are optional; sensible defaults are applied.
        ``allowed_types`` accepts file extensions (``"json"``) and/or
        UTI strings (``"public.image"``).

        Must be called while the run loop is active (e.g. from an action
        handler or lifecycle callback).
        """
        config = self._build_panel_config(
            title=title, prompt=prompt, message=message,
            identifier=identifier, allowed_types=allowed_types,
            directory=directory, shows_hidden_files=shows_hidden_files,
            treats_file_packages_as_directories=treats_file_packages_as_directories,
            can_create_directories=can_create_directories,
            allows_other_file_types=allows_other_file_types,
        )
        if filename is not None:
            config["nameFieldStringValue"] = filename

        config_json = json.dumps(config) if config else None
        return _actionui.app_run_save_panel(config_json)

    @staticmethod
    def _build_panel_config(**kwargs) -> Dict[str, Any]:
        """Build a config dict for file panels, omitting None/default values."""
        config: Dict[str, Any] = {}
        _simple = {
            "title": "title",
            "prompt": "prompt",
            "message": "message",
            "identifier": "identifier",
        }
        for py_key, json_key in _simple.items():
            val = kwargs.get(py_key)
            if val is not None:
                config[json_key] = val

        if kwargs.get("allowed_types") is not None:
            config["allowedContentTypes"] = kwargs["allowed_types"]
        if kwargs.get("directory") is not None:
            config["directoryURL"] = kwargs["directory"]
        if kwargs.get("shows_hidden_files"):
            config["showsHiddenFiles"] = True
        if kwargs.get("treats_file_packages_as_directories"):
            config["treatsFilePackagesAsDirectories"] = True
        if not kwargs.get("can_create_directories", True):
            config["canCreateDirectories"] = False
        if kwargs.get("allows_other_file_types"):
            config["allowsOtherFileTypes"] = True
        return config

    # ------------------------------------------------------------------
    # Alert dialog
    # ------------------------------------------------------------------

    def alert(self, *,
              title: Optional[str] = None,
              message: Optional[str] = None,
              style: str = "informational",
              buttons: Optional[List[str]] = None) -> Optional[str]:
        """Run a modal alert dialog.

        Args:
            title:    Bold heading text.
            message:  Informative text below the title.
            style:    ``"informational"`` (default), ``"warning"``, or
                      ``"critical"``.
            buttons:  List of button titles. The first is the default
                      (rightmost) button.  Defaults to ``["OK"]``.

        Returns:
            The title of the clicked button, or ``None`` on error.

        Example::

            result = app.alert(
                title="Replace Pipeline?",
                message="The current pipeline is not empty.",
                style="warning",
                buttons=["Replace", "Cancel"],
            )
            if result == "Replace":
                ...
        """
        config: Dict[str, Any] = {}
        if title is not None:
            config["title"] = title
        if message is not None:
            config["message"] = message
        if style != "informational":
            config["style"] = style
        if buttons is not None:
            config["buttons"] = buttons
        config_json = json.dumps(config) if config else None
        return _actionui.app_run_alert(config_json)

    # ------------------------------------------------------------------
    # Menu bar
    # ------------------------------------------------------------------

    def load_menu_bar(self, source: Optional[str] = None):
        """Install the default menu bar and optionally apply custom commands.

        Args:
            source: One of the following (or ``None`` for just the defaults):

                * A filesystem path to a JSON file containing an array of
                  ``CommandMenu`` / ``CommandGroup`` elements.
                * A raw JSON string (must start with ``[``).

                The JSON uses the same schema as ActionUI's SwiftUI commands::

                    [
                      {
                        "type": "CommandMenu",
                        "id": 100,
                        "properties": { "name": "Tools" },
                        "children": [
                          {
                            "type": "Button",
                            "id": 101,
                            "properties": {
                              "title": "Run Script",
                              "actionID": "tools.runScript",
                              "keyboardShortcut": { "key": "r", "modifiers": ["command"] }
                            }
                          }
                        ]
                      }
                    ]
        """
        if source is None:
            _actionui.app_load_menu_bar()
            return

        json_string = source
        # Heuristic: if it starts with '[' it's inline JSON; otherwise
        # try to read it as a file path and fall back to passing the
        # raw string to the C layer (which will log a parse error).
        if not source.lstrip().startswith('['):
            import os
            path = os.path.abspath(source)
            if os.path.isfile(path):
                with open(path, 'r') as f:
                    json_string = f.read()

        _actionui.app_load_menu_bar(json_string)


class Window:
    """
    Represents a logical window / view-tree in ActionUI.

    A Window is identified by a UUID and can host one or more SwiftUI views
    loaded from a file:// or http(s):// URL via load_hosting_controller().
    The returned opaque pointer (view_ptr) must be embedded in a platform
    window (NSWindow / UIWindow) by the caller.
    """

    def __init__(self, window_uuid: Optional[str] = None):
        self.uuid = window_uuid or str(uuid.uuid4())
        self._view_ptr: Optional[int] = None

    # ------------------------------------------------------------------
    # Factory methods
    # ------------------------------------------------------------------

    @classmethod
    def from_file(cls, filepath: str,
                  window_uuid: Optional[str] = None,
                  is_content_view: bool = True) -> 'Window':
        """
        Load a window's UI from a local JSON/plist file.

        Args:
            filepath: Filesystem path (converted to file:// URL automatically).
            window_uuid: Optional explicit UUID.
            is_content_view: True → replace the window's root element.

        Returns:
            Window with view_ptr set (or None on error).
        """
        window = cls(window_uuid)
        if not filepath.startswith('file://'):
            import os
            filepath = 'file://' + os.path.abspath(filepath)
        try:
            window._view_ptr = _actionui.load_hosting_controller(
                filepath, window.uuid, is_content_view)
        except RuntimeError:
            window._view_ptr = None
        return window

    @classmethod
    def from_url(cls, url: str,
                 window_uuid: Optional[str] = None,
                 is_content_view: bool = True) -> 'Window':
        """
        Load a window's UI from a remote http(s):// URL.

        Args:
            url: HTTP or HTTPS URL to the UI description file.
            window_uuid: Optional explicit UUID.
            is_content_view: True → replace the window's root element.

        Returns:
            Window with view_ptr set (or None on error).
        """
        window = cls(window_uuid)
        try:
            window._view_ptr = _actionui.load_hosting_controller(
                url, window.uuid, is_content_view)
        except RuntimeError:
            window._view_ptr = None
        return window

    # ------------------------------------------------------------------
    # Type-specific value setters
    # ------------------------------------------------------------------

    def set_int(self, view_id: int, value: int, view_part_id: int = 0):
        """Set an integer value."""
        _actionui.set_int_value(self.uuid, view_id, value, view_part_id)

    def set_double(self, view_id: int, value: float, view_part_id: int = 0):
        """Set a floating-point value."""
        _actionui.set_double_value(self.uuid, view_id, value, view_part_id)

    def set_bool(self, view_id: int, value: bool, view_part_id: int = 0):
        """Set a boolean value."""
        _actionui.set_bool_value(self.uuid, view_id, value, view_part_id)

    def set_string(self, view_id: int, value: str, view_part_id: int = 0):
        """Set a string value."""
        _actionui.set_string_value(self.uuid, view_id, value, view_part_id)

    # ------------------------------------------------------------------
    # Type-specific value getters
    # ------------------------------------------------------------------

    def get_int(self, view_id: int, view_part_id: int = 0) -> Optional[int]:
        """Get an integer value."""
        return _actionui.get_int_value(self.uuid, view_id, view_part_id)

    def get_double(self, view_id: int, view_part_id: int = 0) -> Optional[float]:
        """Get a floating-point value."""
        return _actionui.get_double_value(self.uuid, view_id, view_part_id)

    def get_bool(self, view_id: int, view_part_id: int = 0) -> Optional[bool]:
        """Get a boolean value."""
        return _actionui.get_bool_value(self.uuid, view_id, view_part_id)

    def get_string(self, view_id: int, view_part_id: int = 0) -> Optional[str]:
        """Get a string value."""
        return _actionui.get_string_value(self.uuid, view_id, view_part_id)

    # ------------------------------------------------------------------
    # Generic value access (auto-detects type)
    # ------------------------------------------------------------------

    def set_value(self, view_id: int, value: Any, view_part_id: int = 0):
        """
        Set a value with automatic type dispatch.

        bool/int/float/str are forwarded directly; anything else is
        JSON-serialised and sent as a JSON string.
        """
        if isinstance(value, bool):
            self.set_bool(view_id, value, view_part_id)
        elif isinstance(value, int):
            self.set_int(view_id, value, view_part_id)
        elif isinstance(value, float):
            self.set_double(view_id, value, view_part_id)
        elif isinstance(value, str):
            self.set_string(view_id, value, view_part_id)
        else:
            _actionui.set_value_from_json(self.uuid, view_id,
                                        json.dumps(value), view_part_id)

    def get_value(self, view_id: int, view_part_id: int = 0) -> Optional[Any]:
        """
        Get a value via JSON round-trip (preserves the original type).

        Returns None if the view is not found.
        """
        raw = _actionui.get_value_as_json(self.uuid, view_id, view_part_id)
        if raw is None:
            return None
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            return raw

    # ------------------------------------------------------------------
    # Element column count
    # ------------------------------------------------------------------

    def get_column_count(self, view_id: int) -> int:
        """
        Return the number of data columns for a table/list element.

        Returns 0 for non-table elements or unknown view IDs.
        """
        return _actionui.get_element_column_count(self.uuid, view_id)

    # ------------------------------------------------------------------
    # Element rows (table / list)
    # ------------------------------------------------------------------

    def get_rows(self, view_id: int) -> Optional[List[List[str]]]:
        """
        Return all content rows for a table/list element.

        Returns None if the element is not a table or is not found.
        """
        raw = _actionui.get_element_rows_json(self.uuid, view_id)
        if raw is None:
            return None
        return json.loads(raw)

    def set_rows(self, view_id: int, rows: List[List[str]]):
        """Replace all content rows (clears selection if it becomes invalid)."""
        _actionui.set_element_rows_json(self.uuid, view_id, json.dumps(rows))

    def append_rows(self, view_id: int, rows: List[List[str]]):
        """Append rows to a table/list element's existing content."""
        _actionui.append_element_rows_json(self.uuid, view_id, json.dumps(rows))

    def clear_rows(self, view_id: int):
        """Clear all content rows, preserving column definitions."""
        _actionui.clear_element_rows(self.uuid, view_id)

    # ------------------------------------------------------------------
    # Element properties (structural / layout)
    # ------------------------------------------------------------------

    def get_property(self, view_id: int, name: str) -> Optional[Any]:
        """
        Get a structural property value (e.g. "columns", "disabled").

        Returns None if not found.
        """
        raw = _actionui.get_element_property_json(self.uuid, view_id, name)
        if raw is None:
            return None
        return json.loads(raw)

    def set_property(self, view_id: int, name: str, value: Any):
        """
        Set a structural property value.

        The value is re-validated through the element's validateProperties
        function inside ActionUI.
        """
        _actionui.set_element_property_json(self.uuid, view_id, name,
                                          json.dumps(value))

    # ------------------------------------------------------------------
    # Element state (runtime / dynamic)
    # ------------------------------------------------------------------

    def get_state(self, view_id: int, key: str) -> Optional[Any]:
        """
        Get a runtime state value by key (e.g. "isLoading", "canGoBack").

        Returns None if the view or key is not found.
        """
        raw = _actionui.get_element_state_json(self.uuid, view_id, key)
        if raw is None:
            return None
        return json.loads(raw)

    def get_state_string(self, view_id: int, key: str) -> Optional[str]:
        """Get a runtime state value as a plain string."""
        return _actionui.get_element_state_string(self.uuid, view_id, key)

    def set_state(self, view_id: int, key: str, value: Any):
        """
        Set a runtime state value.

        The update is rejected (with an error log) if the new value's type
        differs from the existing value's type.
        """
        _actionui.set_element_state_json(self.uuid, view_id, key,
                                       json.dumps(value))

    def set_state_from_string(self, view_id: int, key: str, value: str):
        """
        Set a runtime state value by parsing a string into the existing type.

        If the key does not yet exist, the string is stored as-is.
        """
        _actionui.set_element_state_from_string(self.uuid, view_id, key, value)

    # ------------------------------------------------------------------
    # Element info
    # ------------------------------------------------------------------

    def get_element_info(self) -> Dict[int, str]:
        """
        Return a mapping of positive view IDs to their ActionUI view-type
        strings for this window (e.g. {2: "TextField", 3: "Button"}).

        Auto-assigned negative IDs and ID 0 are excluded.
        Returns an empty dict if no window or no positive-ID elements exist.
        """
        raw = _actionui.get_element_info_json(self.uuid)
        if raw is None:
            return {}
        return {int(k): v for k, v in json.loads(raw).items()}

    # ------------------------------------------------------------------
    # Properties
    # ------------------------------------------------------------------

    @property
    def view_ptr(self) -> Optional[int]:
        """Opaque native pointer (int) for AppKit/UIKit integration."""
        return self._view_ptr


# ---------------------------------------------------------------------------
# Module-level convenience functions
# ---------------------------------------------------------------------------

def get_version() -> str:
    """Return the ActionUI version string."""
    return _actionui.get_version() or "unknown"


def get_last_error() -> Optional[str]:
    """Return the last adapter error message, or None."""
    return _actionui.get_last_error()


def clear_error():
    """Clear the stored last error."""
    _actionui.clear_error()


__all__ = [
    'Application',
    'Window',
    'ActionContext',
    'LogLevel',
    'Logger',
    'ActionUIError',
    'get_version',
    'get_last_error',
    'clear_error',
]
