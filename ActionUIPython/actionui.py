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
from typing import Optional, Callable, Any, Dict, List, Tuple, Union
from enum import IntEnum, Enum
from dataclasses import dataclass, field


# The remote bridge's environment contract (ActionUIRemote/PROTOCOL.md section 9). A child
# process reads these two to find the host and the window it was started for.
REMOTE_ENDPOINT_ENV = "ACTIONUI_REMOTE_ENDPOINT"
REMOTE_WINDOW_ENV = "ACTIONUI_WINDOW_UUID"
# Set by the framework when it requires one; a child sends it back and is let in.
REMOTE_TOKEN_ENV = "ACTIONUI_REMOTE_TOKEN"


class LogLevel(IntEnum):
    """Log levels for ActionUI.  Values match ActionUILogLevel in ActionUIC.h."""
    ERROR   = _actionui.LOG_ERROR
    WARNING = _actionui.LOG_WARNING
    INFO    = _actionui.LOG_INFO
    DEBUG   = _actionui.LOG_DEBUG
    VERBOSE = _actionui.LOG_VERBOSE


class ModalStyle(str, Enum):
    """Presentation style for window-level modals."""
    SHEET             = "sheet"
    FULL_SCREEN_COVER = "fullScreenCover"


class ButtonRole(str, Enum):
    """Role for dialog / alert buttons."""
    DEFAULT     = "default"       # Normal prominence (no special role)
    CANCEL      = "cancel"        # Appears last; bold on iOS
    DESTRUCTIVE = "destructive"   # Red tint


class InsertPosition(IntEnum):
    """Position for insertElement / insertRow structural mutations.

    For AT, the associated index is passed as ``position_param`` /
    ``position_index``.  For BEFORE / AFTER, it is the sibling view ID.
    BEFORE and AFTER are invalid for Grid row containers.
    """
    APPEND  = 0   # Add after the last existing child
    PREPEND = 1   # Add before the first existing child
    AT      = 2   # Insert at a specific index (position_param = index)
    BEFORE  = 3   # Insert before a sibling (position_param = sibling viewID)
    AFTER   = 4   # Insert after a sibling  (position_param = sibling viewID)


@dataclass
class DialogButton:
    """A button descriptor for window-level alerts and confirmation dialogs.

    Args:
        title:     Button label text.
        role:      ``ButtonRole.DEFAULT`` (or ``None``) for a plain button,
                   ``ButtonRole.CANCEL`` to mark it as the cancel action, or
                   ``ButtonRole.DESTRUCTIVE`` for a red-tinted destructive action.
        action_id: ActionID fired when the button is tapped; ``None`` for
                   dismiss-only buttons.

    Example::

        buttons = [
            DialogButton("Delete", role=ButtonRole.DESTRUCTIVE, action_id="item.delete"),
            DialogButton("Cancel", role=ButtonRole.CANCEL),
        ]
    """
    title:     str
    role:      Optional[ButtonRole] = None
    action_id: Optional[str]        = None

    def _to_dict(self) -> Dict[str, Any]:
        d: Dict[str, Any] = {"title": self.title}
        if self.role is not None and self.role != ButtonRole.DEFAULT:
            d["role"] = self.role.value
        if self.action_id is not None:
            d["actionID"] = self.action_id
        return d


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
        self._remote_server_atexit_registered = False

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

    # ------------------------------------------------------------------
    # Remote bridge (out-of-process access to this app's windows)
    # ------------------------------------------------------------------

    def start_remote_server(self, path: Optional[str] = None) -> str:
        """Start the remote bridge, so child processes can read and drive this app's windows.

        A child reaches the windows with the ``actionui_remote`` module or with
        ``python3 -m actionui_remote``, both shipped in ``ActionUIRemote/Python``.  The wire
        contract is ``ActionUIRemote/PROTOCOL.md``.  Every request runs on the main thread
        against the same model the UI uses, so a worker sees exactly what is on screen.

        Which window a child should drive is this app's to communicate: export
        ``ACTIONUI_WINDOW_UUID`` for it, or pass the UUID on its command line.

        Args:
            path: Socket path.  Defaults to one per process in the user's temporary
                  directory.  A Unix socket path is capped at 103 bytes.  Anything already
                  at *path* is unlinked before binding, so pass a path of your own making,
                  not a file that matters.

        Returns:
            The socket path the server bound.  It is also exported as
            ``ACTIONUI_REMOTE_ENDPOINT``, so processes spawned afterwards inherit it and
            need no configuration.

        Raises:
            RuntimeError: a server is already running, or the socket could not be created.
                          The reason is logged.

        The server is stopped and its socket removed when the application terminates, and
        at interpreter exit for a script that never started the run loop.  (``app.run()``
        never returns: AppKit ends the process in ``exit()``, which does not run ``atexit``.)

        Example::

            endpoint = app.start_remote_server()
            subprocess.run(["python3", "worker.py"],
                           env={**os.environ, "ACTIONUI_WINDOW_UUID": window.uuid})
        """
        import atexit
        import os
        endpoint = _actionui.app_start_remote_server(path)
        # The framework called setenv, which os.environ does not see; keep the two in step.
        os.environ[REMOTE_ENDPOINT_ENV] = endpoint
        # Same for the token, when the framework minted one. Without this a child launched with
        # the documented env={**os.environ, ...} pattern would be refused, because the value it
        # needs would be in the real environment and not in the copy. Asked of the framework
        # rather than read back out of the environment with getenv: the accessor returns the
        # value captured when the server started, so it stays right for a host that unexports
        # the variable to keep the token off `ps`.
        token = _actionui.app_remote_server_token()
        if token is None:
            os.environ.pop(REMOTE_TOKEN_ENV, None)
        else:
            os.environ[REMOTE_TOKEN_ENV] = token
        if not self._remote_server_atexit_registered:
            atexit.register(self.stop_remote_server)
            self._remote_server_atexit_registered = True
        return endpoint

    def stop_remote_server(self):
        """Stop the remote bridge and remove its socket.  Does nothing if it is not running."""
        import os
        was_running = _actionui.app_remote_server_endpoint() is not None
        _actionui.app_stop_remote_server()
        if was_running:
            # Only when it was ours: an app that is itself a remote child inherited this
            # variable from its parent and must keep it.
            os.environ.pop(REMOTE_ENDPOINT_ENV, None)
            os.environ.pop(REMOTE_TOKEN_ENV, None)

    @property
    def remote_server_endpoint(self) -> Optional[str]:
        """The running server's socket path, or ``None`` when it is not running."""
        return _actionui.app_remote_server_endpoint()

    @property
    def remote_server_token(self) -> Optional[str]:
        """The token the running server requires, or ``None`` when it requires none.

        Children spawned after :meth:`start_remote_server` inherit it in
        ``ACTIONUI_REMOTE_TOKEN`` and ``actionui_remote`` sends it unasked, so a host normally
        never needs this.  It is here for a host that hands the token to a child some other way -
        on an inherited descriptor, which keeps it out of ``ps``; see ``PROTOCOL.md`` section 10.
        """
        return _actionui.app_remote_server_token()

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
    # Content size limits
    # ------------------------------------------------------------------

    def content_size_limits(self) -> Optional[Tuple[float, float, float, float]]:
        """
        Return the loaded root element's content size limits as a
        (min_width, min_height, max_width, max_height) tuple.

        The minimum is what the SwiftUI content reports for a zero size
        proposal, the maximum for an infinite one; flexible axes report a very
        large maximum, and a fixed root frame reports min == max (make the
        hosting window non-user-resizable in that case). Measured on the bare
        root element, bypassing the window-level modal/toast wrapper.
        Returns None if the window has no loaded description.
        """
        try:
            return _actionui.get_content_size_limits(self.uuid)
        except RuntimeError:
            return None

    # ------------------------------------------------------------------
    # Type-specific value setters
    # ------------------------------------------------------------------

    def set_int(self, view_id: int, value: int):
        """Set an integer value."""
        _actionui.set_int_value(self.uuid, view_id, 0, value)

    def set_double(self, view_id: int, value: float):
        """Set a floating-point value."""
        _actionui.set_double_value(self.uuid, view_id, 0, value)

    def set_bool(self, view_id: int, value: bool):
        """Set a boolean value."""
        _actionui.set_bool_value(self.uuid, view_id, 0, value)

    def set_string(self, view_id: int, value: str):
        """Set a string value."""
        _actionui.set_string_value(self.uuid, view_id, 0, value)

    # ------------------------------------------------------------------
    # Type-specific value setters with view part id
    # ------------------------------------------------------------------

    def set_view_part_int(self, view_id: int, view_part_id: int, value: int):
        """Set an integer value."""
        _actionui.set_int_value(self.uuid, view_id, view_part_id, value)

    def set_view_part_double(self, view_id: int, view_part_id: int, value: float):
        """Set a floating-point value."""
        _actionui.set_double_value(self.uuid, view_id, view_part_id, value)

    def set_view_part_bool(self, view_id: int, view_part_id: int, value: bool):
        """Set a boolean value."""
        _actionui.set_bool_value(self.uuid, view_id, view_part_id, value)

    def set_view_part_string(self, view_id: int, view_part_id: int, value: str):
        """Set a string value."""
        _actionui.set_string_value(self.uuid, view_id, view_part_id, value)

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

    def set_value(self, view_id: int, view_part_id, value: Any):
        """
        Set a value with automatic type dispatch.

        bool/int/float/str are forwarded directly; anything else is
        JSON-serialised and sent as a JSON string.
        """
        if isinstance(value, bool):
            self.set_view_part_bool(view_id, view_part_id, value)
        elif isinstance(value, int):
            self.set_view_part_int(view_id, view_part_id, value)
        elif isinstance(value, float):
            self.set_view_part_double(view_id, view_part_id, value)
        elif isinstance(value, str):
            self.set_view_part_string(view_id, view_part_id, value)
        else:
            _actionui.set_value_from_json(self.uuid, view_id, view_part_id,
                                         json.dumps(value))

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
    # String value access with optional content-type
    # ------------------------------------------------------------------

    def set_value_from_string(self, view_id: int, view_part_id: int, value: str, content_type: Optional[str] = None) -> bool:
        """
        Set a view's value from a string with an optional content-type hint.

        content_type may be "plain" (default), "markdown", "html", "rtf", or "json".
        For a TextEditor with markdown content, "markdown" / "html" / "rtf" parse the
        string into an AttributedString.
        Returns True on success.
        """
        return _actionui.set_value_from_string(self.uuid, view_id, view_part_id, value, content_type)

    def get_value_as_string(self, view_id: int, view_part_id: int, content_type: Optional[str] = None) -> Optional[str]:
        """
        Get a view's value as a string with an optional content-type hint.

        content_type may be "plain" (default, extracts plain text) or "json"
        (returns the JSON runs array for TextEditor with markdown content).
        Returns None if the view is not found.
        """
        return _actionui.get_value_as_string(self.uuid, view_id, view_part_id, content_type)

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
    # Element selection (Table / List)
    # ------------------------------------------------------------------

    def select_row(self, view_id: int, index: int) -> bool:
        """
        Select a Table/List row by its 0-based index without altering the rows.

        An index outside 0..<rowCount clears the selection. Fires no actionID.
        Returns True if a row was selected, False if the index was out of range
        (selection cleared) or the element is not a Table/List.
        """
        return bool(_actionui.select_element_row_by_index(self.uuid, view_id, index))

    def select_row_with_content(self, view_id: int, text: str, column: Optional[int] = None) -> int:
        """
        Select the first row whose column value matches ``text`` (exact, case-sensitive).

        When ``column`` is None, matches any column; otherwise matches the given 0-based
        column only. Fires no actionID. Returns the 0-based index of the selected row,
        or -1 if no row matched.
        """
        col = column if column is not None else -1
        return int(_actionui.select_element_row_with_content(self.uuid, view_id, text, col))

    def clear_selection(self, view_id: int):
        """Clear the current selection of a Table/List element."""
        _actionui.clear_element_selection(self.uuid, view_id)

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
    # Runtime structural mutations
    # ------------------------------------------------------------------

    def insert_element(self,
                       parent_id: int,
                       element: Union[str, Dict[str, Any]],
                       container: Optional[str] = None,
                       position: InsertPosition = InsertPosition.APPEND,
                       position_param: int = 0) -> int:
        """Insert a new element into a flat container at runtime.

        Args:
            parent_id:       View ID of the container to insert into.
            element:         JSON string or dict describing the new view.
            container:            Container name (e.g. ``"children"``). If ``None``,
                             auto-derived when the container has exactly one
                             flat container.
            position:        Insert position — 0=append (default), 1=prepend,
                             2=at (``position_param`` is the target index),
                             3=before (``position_param`` is sibling view ID),
                             4=after  (``position_param`` is sibling view ID).
            position_param:  Index or sibling view ID for positions 2–4.

        Returns:
            The newly assigned view ID of the inserted element.

        Raises:
            RuntimeError: If the C layer reports an error.
        """
        if isinstance(element, dict):
            element = json.dumps(element)
        return _actionui.insert_element(
            self.uuid, parent_id, element, container, position, position_param
        )

    def insert_row(self,
                   parent_id: int,
                   cells: Union[str, List[Dict[str, Any]]],
                   container: Optional[str] = None,
                   position: InsertPosition = InsertPosition.APPEND,
                   position_index: int = 0) -> List[int]:
        """Insert a new row of cells into a Grid rows container at runtime.

        Args:
            parent_id:      View ID of the Grid container.
            cells:          JSON string or list of dicts, each describing one
                            cell in the new row.
            container:           Container name (e.g. ``"rows"``). If ``None``,
                            auto-derived when the container has exactly one
                            rows container.
            position:       Insert position — 0=append (default), 1=prepend,
                            2=at (``position_index`` is the target row index).
            position_index: Row index for position 2 (at).

        Returns:
            List of newly assigned view IDs for each cell in the row.

        Raises:
            RuntimeError: If the C layer reports an error.
        """
        if isinstance(cells, list):
            cells = json.dumps(cells)
        return _actionui.insert_row(
            self.uuid, parent_id, cells, container, position, position_index
        )

    def remove_element(self, view_id: int):
        """Remove a view from its parent container at runtime.

        Also removes all descendant views (cascade cleanup).

        Args:
            view_id: ID of the view to remove.

        Raises:
            RuntimeError: If the C layer reports an error.
        """
        _actionui.remove_element(self.uuid, view_id)

    # ------------------------------------------------------------------
    # Modal presentation (window-level / Tier 2)
    # ------------------------------------------------------------------

    def present_modal(self,
                      source: str,
                      format: str = "json",
                      style: ModalStyle = ModalStyle.SHEET,
                      on_dismiss_action_id: Optional[str] = None):
        """Present a window-level modal sheet or full-screen cover.

        The modal's view hierarchy is loaded from *source*, which may be a
        JSON/plist **string** or a filesystem **path** (converted to a string
        automatically if it ends with ``.json`` or ``.plist``).

        Args:
            source:               JSON/plist string describing the modal UI.
            format:               ``"json"`` (default) or ``"plist"``.
            style:                :class:`ModalStyle` — ``SHEET`` (default) or
                                  ``FULL_SCREEN_COVER``.
            on_dismiss_action_id: Optional actionID fired when the modal is
                                  dismissed (by swipe, button, or
                                  :meth:`dismiss_modal`).

        Raises:
            RuntimeError: If the C layer reports an error (e.g., unknown
                          window UUID or malformed JSON).

        Example::

            window.present_modal(
                open("settings.json").read(),
                style=ModalStyle.SHEET,
                on_dismiss_action_id="settings.closed",
            )
        """
        _actionui.present_modal(
            self.uuid, source, format,
            style.value if isinstance(style, ModalStyle) else style,
            on_dismiss_action_id,
        )

    def dismiss_modal(self):
        """Dismiss the active window-level modal (also fires onDismissActionID)."""
        _actionui.dismiss_modal(self.uuid)

    def present_alert(self,
                      title: str,
                      message: Optional[str] = None,
                      buttons: Optional[List[DialogButton]] = None):
        """Present a window-level alert dialog.

        Args:
            title:   Alert title.
            message: Optional informative text below the title.
            buttons: List of :class:`DialogButton`; defaults to a single
                     OK/cancel button when ``None``.

        Example::

            window.present_alert(
                "Connection Failed",
                message="Please check your network connection.",
            )

            window.present_alert(
                "Delete Item?",
                message="This action cannot be undone.",
                buttons=[
                    DialogButton("Delete", role=ButtonRole.DESTRUCTIVE,
                                 action_id="item.delete.confirmed"),
                    DialogButton("Cancel", role=ButtonRole.CANCEL),
                ],
            )
        """
        buttons_json = (json.dumps([b._to_dict() for b in buttons])
                        if buttons is not None else None)
        _actionui.present_alert(self.uuid, title, message, buttons_json)

    def present_confirmation_dialog(self,
                                    title: str,
                                    message: Optional[str] = None,
                                    buttons: Optional[List[DialogButton]] = None):
        """Present a window-level confirmation dialog (action sheet on macOS/iOS).

        Args:
            title:   Dialog title.
            message: Optional informative text.
            buttons: List of :class:`DialogButton`.  An empty list is used if
                     ``None`` is passed.

        Example::

            window.present_confirmation_dialog(
                "Save changes before closing?",
                message="Unsaved changes will be lost.",
                buttons=[
                    DialogButton("Save",       action_id="doc.save"),
                    DialogButton("Don't Save", role=ButtonRole.DESTRUCTIVE,
                                 action_id="doc.discard"),
                    DialogButton("Cancel",     role=ButtonRole.CANCEL),
                ],
            )
        """
        buttons_json = (json.dumps([b._to_dict() for b in buttons])
                        if buttons is not None else None)
        _actionui.present_confirmation_dialog(self.uuid, title, message, buttons_json)

    def dismiss_dialog(self):
        """Dismiss the active window-level alert or confirmation dialog.

        SwiftUI dismisses dialogs automatically when a button is tapped;
        call this only when you need to dismiss programmatically without
        any button interaction.
        """
        _actionui.dismiss_dialog(self.uuid)

    def present_toast(self,
                      message: str,
                      duration: float = 4.0,
                      action_title: Optional[str] = None,
                      action_id: Optional[str] = None):
        """Present a transient, auto-dismissing toast (snackbar).

        The toast is pinned above the window content and dismisses itself
        after *duration* seconds.  If a toast is already visible, the new one
        is queued and shown after the current dismisses (rapid posts coalesce
        into an ordered sequence).

        Args:
            message:      The toast text.
            duration:     Seconds before auto-dismiss (default ``4.0``).
            action_title: Optional inline action button title (e.g. ``"Undo"``).
                          Supply together with *action_id*.
            action_id:    Optional actionID fired when the inline action button
                          is tapped (then the toast dismisses).

        Example::

            window.present_toast("All changes synced")

            window.present_toast(
                "Logged Evening meds",
                action_title="Undo",
                action_id="task.undo",
            )
        """
        _actionui.present_toast(self.uuid, message, duration, action_title, action_id)

    def dismiss_toast(self):
        """Dismiss the current toast, showing the next queued one if any.

        The auto-dismiss timer and the inline action button call this for you;
        use it only to dismiss a toast programmatically.
        """
        _actionui.dismiss_toast(self.uuid)

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
    'ModalStyle',
    'ButtonRole',
    'InsertPosition',
    'DialogButton',
    'get_version',
    'get_last_error',
    'clear_error',
]
